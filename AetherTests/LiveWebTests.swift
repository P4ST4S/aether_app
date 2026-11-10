import Foundation
import Testing
@testable import Aether

struct LiveWebTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AETHER_LIVE_WEB_TESTS"] == "1"))
    func readsRealPublicPageAndSearchResults() async throws {
        let service = WebResearchService()
        print("Checking direct public page")
        let direct = try await service.retrieve(for: "Summarize https://www.swift.org/")
        #expect(direct.first?.kind == .page)
        #expect(direct.first?.excerpt.lowercased().contains("swift") == true)
        print("Checking live search")
        let results = try await service.retrieve(for: "site:swift.org Swift programming documentation")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.url.scheme == "https" && !$0.excerpt.isEmpty })
        print("Live web sources: \(results.map { "\($0.title) [\($0.kind.rawValue)] \($0.url.absoluteString)" }.joined(separator: " | "))")
    }
}
