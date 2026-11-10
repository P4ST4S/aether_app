import Foundation

struct WebSource: Codable, Sendable, Identifiable, Equatable {
    enum Kind: String, Codable, Sendable { case page, searchSnippet }
    let id: Int
    let title: String
    let url: URL
    let excerpt: String
    let kind: Kind
    var retrievedAt: Date = .now
}

enum WebError: LocalizedError, Equatable {
    case unsafeURL, unavailable, unsupportedContent, tooLarge, noResults, invalidSearchResponse
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .unsafeURL: "Web access accepts public HTTPS pages only. Local addresses, credentials, and custom ports are blocked."
        case .unavailable: "The website could not be reached. Check your connection or try another public HTTPS URL."
        case .unsupportedContent: "This URL is not a readable text page. PDFs, downloads, and pages requiring JavaScript or sign-in are not supported."
        case .tooLarge: "This page is too large to read safely. Try a smaller page."
        case .noResults: "No usable web sources were found. Try a more precise search or paste a public HTTPS URL."
        case .invalidSearchResponse: "Web search is temporarily unavailable. Retry later or paste a public HTTPS URL to read it directly."
        case let .http(status): "The website returned HTTP \(status). Try another source or turn Web off to chat offline."
        }
    }
}

protocol WebRetrieving: Sendable {
    func retrieve(for question: String) async throws -> [WebSource]
}
