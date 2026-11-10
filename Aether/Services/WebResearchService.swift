import Foundation
import SwiftSoup

struct SearchResult: Sendable, Equatable {
    let title: String
    let url: URL
    let snippet: String
}

final class SearchFeedParser: NSObject, XMLParserDelegate {
    private var results: [SearchResult] = []
    private var insideItem = false
    private var element = ""
    private var fields: [String: String] = [:]

    static func parse(_ data: Data) throws -> [SearchResult] {
        guard data.count <= 256_000 else { throw WebError.tooLarge }
        let prefix = String(decoding: data, as: UTF8.self).uppercased()
        guard !prefix.contains("<!DOCTYPE"), !prefix.contains("<!ENTITY") else { throw WebError.invalidSearchResponse }
        let delegate = SearchFeedParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = delegate
        guard parser.parse() else { throw WebError.invalidSearchResponse }
        return delegate.results
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "item" { insideItem = true; fields = [:] }
        element = elementName
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideItem, ["title", "link", "description"].contains(element) { fields[element, default: ""] += string }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self)) }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            if let raw = fields["link"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               var components = URLComponents(string: raw) {
                if components.scheme == "http" { components.scheme = "https"; if components.port == 80 { components.port = nil } }
                if let url = components.url, let safe = try? PublicWebURL.validate(url), !results.contains(where: { $0.url == safe }) {
                    results.append(SearchResult(title: String((fields["title"] ?? safe.host ?? "Web source").prefix(200)), url: safe,
                                                snippet: WebPageParser.plainText(fields["description"] ?? "", limit: 800)))
                }
            }
            insideItem = false
        }
        element = ""
    }
}

enum WebPageParser {
    static func redirect(in data: Data, relativeTo url: URL) throws -> URL? {
        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
        for meta in try document.select("meta[http-equiv]").array() {
            guard try meta.attr("http-equiv").lowercased() == "refresh" else { continue }
            let parts = try meta.attr("content").split(separator: ";", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2, let delay = Double(parts[0]), (0...1).contains(delay), parts[1].lowercased().hasPrefix("url=") else { continue }
            let value = String(parts[1].dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if let target = URL(string: value, relativeTo: url)?.absoluteURL { return try PublicWebURL.validate(target) }
        }
        return nil
    }
    static func plainText(_ html: String, limit: Int) -> String {
        guard let document = try? SwiftSoup.parse(html) else { return "" }
        _ = try? document.select("script, style, noscript, nav, footer, header, aside, form, svg, iframe, object, embed, [hidden], [aria-hidden=true]").remove()
        let root = (try? document.select("main, article, [role=main]").first()) ?? document.body()
        return String(((try? root?.text()) ?? "").prefix(limit))
    }
    static func page(_ data: Data, url: URL, id: Int, mimeType: String = "text/html") throws -> WebSource {
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let title: String
        let text: String
        if mimeType == "text/plain" {
            title = url.lastPathComponent
            text = String(html.prefix(12_000))
        } else {
            let document = try SwiftSoup.parse(html)
            title = String(try document.title().prefix(200))
            text = plainText(html, limit: 12_000)
        }
        guard text.count >= 80 else { throw WebError.unsupportedContent }
        return WebSource(id: id, title: title.isEmpty ? (url.host ?? "Web source") : title, url: url, excerpt: text, kind: .page)
    }
}

actor WebResearchService: WebRetrieving {
    private let client = PublicWebClient()

    func retrieve(for question: String) async throws -> [WebSource] {
        let direct = Self.urls(in: question)
        if !direct.isEmpty {
            var sources: [WebSource] = []
            for url in direct.prefix(3) {
                let page = try await client.download(url)
                sources.append(try WebPageParser.page(page.data, url: page.url, id: sources.count + 1, mimeType: page.mimeType))
            }
            return sources
        }
        guard var url = URLComponents(string: "https://www.bing.com/search") else { throw WebError.unavailable }
        url.queryItems = [URLQueryItem(name: "format", value: "rss"), URLQueryItem(name: "q", value: String(question.prefix(500)))]
        guard let searchURL = url.url else { throw WebError.unavailable }
        let feed = try await client.download(searchURL, search: true)
        let results = Array(try SearchFeedParser.parse(feed.data).prefix(3))
        guard !results.isEmpty else { throw WebError.noResults }
        let sources = try await withThrowingTaskGroup(of: WebSource?.self) { group in
            for (index, result) in results.enumerated() {
                group.addTask { [client] in
                    do {
                        let page = try await client.download(result.url)
                        return try WebPageParser.page(page.data, url: page.url, id: index + 1, mimeType: page.mimeType)
                    } catch {
                        if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                        // Search snippets stay explicitly labeled when a publisher blocks text retrieval.
                        guard !result.snippet.isEmpty else { return nil }
                        return WebSource(id: index + 1, title: result.title, url: result.url, excerpt: result.snippet, kind: .searchSnippet)
                    }
                }
            }
            var collected: [WebSource] = []
            for try await source in group { if let source { collected.append(source) } }
            return collected.sorted { $0.id < $1.id }
        }
        guard !sources.isEmpty else { throw WebError.noResults }
        return sources
    }

    static func urls(in question: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var urls: [URL] = []
        for match in detector.matches(in: question, range: NSRange(question.startIndex..., in: question)) {
            if let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), !urls.contains(url) { urls.append(url) }
        }
        return urls
    }
}
