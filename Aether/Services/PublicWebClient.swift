import Darwin
import Foundation

// Web requests have their own session: they never reuse Ollama requests or credentials.
private final class WebSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        // Redirects are followed manually, after checking the destination again.
        nil
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
            ? (.performDefaultHandling, nil) : (.cancelAuthenticationChallenge, nil)
    }
}

enum PublicWebURL {
    static func validate(_ url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https", let host = components.host?.lowercased(),
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              host.contains("."), !host.hasSuffix("."),
              !host.contains(":"), host.first != "[",
              !host.allSatisfy({ $0.isNumber || $0 == "." }),
              ![".local", ".localhost", ".internal", ".lan", ".home"].contains(where: host.hasSuffix),
              !["localhost", "metadata.google.internal"].contains(host),
              url.absoluteString.utf8.count <= 4096 else { throw WebError.unsafeURL }
        components.fragment = nil
        guard let cleaned = components.url else { throw WebError.unsafeURL }
        return cleaned
    }

    static func isPublicAddress(_ address: String) -> Bool {
        var ipv4 = in_addr()
        if inet_pton(AF_INET, address, &ipv4) == 1 {
            let octets = address.split(separator: ".").compactMap { UInt8($0) }
            guard octets.count == 4 else { return false }
            let a = octets[0], b = octets[1]
            return a > 0 && a < 224 && a != 10 && a != 127
                && !(a == 100 && (64...127).contains(b))
                && !(a == 169 && b == 254) && !(a == 172 && (16...31).contains(b))
                && !(a == 192 && [0, 168].contains(b))
                && !(a == 198 && [18, 19, 51].contains(b))
                && !(a == 203 && b == 0 && octets[2] == 113)
        }
        var ipv6 = in6_addr()
        guard inet_pton(AF_INET6, address, &ipv6) == 1 else { return false }
        let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
        // Only globally routable unicast; mapped/private/link-local/multicast are excluded.
        guard bytes[0] & 0xE0 == 0x20 else { return false }
        if bytes[0...3].elementsEqual([0x20, 0x01, 0x0d, 0xb8]) { return false }
        return true
    }

    static func validateDNS(for url: URL) async throws {
        guard let host = url.host else { throw WebError.unsafeURL }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { throw WebError.unavailable }
        defer { freeaddrinfo(first) }
        var current: UnsafeMutablePointer<addrinfo>? = first
        var found = false
        while let record = current {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(record.pointee.ai_addr, record.pointee.ai_addrlen,
                              &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { throw WebError.unsafeURL }
            let count = buffer.firstIndex(of: 0) ?? buffer.count
            let numeric = String(decoding: buffer.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard isPublicAddress(numeric) else { throw WebError.unsafeURL }
            found = true
            current = record.pointee.ai_next
        }
        guard found else { throw WebError.unavailable }
    }
}

actor PublicWebClient {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration, delegate: WebSessionDelegate(), delegateQueue: nil)
    }

    func download(_ initialURL: URL, search: Bool = false) async throws -> (data: Data, url: URL, mimeType: String) {
        var url = try PublicWebURL.validate(initialURL)
        let limit = search ? 256_000 : 1_500_000
        for _ in 0..<4 {
            try Task.checkCancellation()
            try await PublicWebURL.validateDNS(for: url)
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.setValue("Aether/1.0 (macOS; text-only web retrieval)", forHTTPHeaderField: "User-Agent")
            request.setValue(search ? "application/rss+xml, application/xml, text/xml" : "text/html, application/xhtml+xml, text/plain", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { throw WebError.unavailable }
            if [301, 302, 303, 307, 308].contains(http.statusCode) {
                guard let location = http.value(forHTTPHeaderField: "Location"),
                      let destination = URL(string: location, relativeTo: url)?.absoluteURL else { throw WebError.unsafeURL }
                url = try PublicWebURL.validate(destination)
                continue
            }
            guard (200..<300).contains(http.statusCode) else { throw WebError.http(http.statusCode) }
            let mime = http.mimeType?.lowercased() ?? ""
            let allowed = search ? ["application/rss+xml", "application/xml", "text/xml"] : ["text/html", "application/xhtml+xml", "text/plain"]
            guard allowed.contains(mime) else { throw WebError.unsupportedContent }
            guard response.expectedContentLength <= limit else { throw WebError.tooLarge }
            var data = Data()
            data.reserveCapacity(min(limit, max(0, Int(response.expectedContentLength))))
            for try await byte in bytes {
                guard data.count < limit else { throw WebError.tooLarge }
                data.append(byte)
                if data.count.isMultiple(of: 4096) { try Task.checkCancellation() }
            }
            try Task.checkCancellation()
            if !search, mime != "text/plain", let redirect = try WebPageParser.redirect(in: data, relativeTo: url) {
                url = redirect
                continue
            }
            return (data, url, mime)
        }
        throw WebError.unavailable
    }
}
