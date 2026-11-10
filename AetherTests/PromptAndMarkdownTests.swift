import Foundation
import Testing
@testable import Aether

struct PromptAndMarkdownTests {
    @Test func trimsOnlyWholeOldTurnsAndKeepsLatestQuestion() throws {
        let history = [
            ChatMessage(role: "user", content: String(repeating: "x", count: 2000)),
            ChatMessage(role: "assistant", content: "Old answer"),
            ChatMessage(role: "user", content: "Recent"),
            ChatMessage(role: "assistant", content: "Recent answer"),
            ChatMessage(role: "user", content: "Latest")
        ]
        let result = try PromptBuilder.messages(from: history, system: "System", context: 2048, output: 1024)
        #expect(result.map(\.content) == ["System", "Recent", "Recent answer", "Latest"])
    }

    @Test func dropsUnansweredOldUserTurnAndRejectsOversizedPrompt() throws {
        let history = [ChatMessage(role: "user", content: "Failed"), ChatMessage(role: "user", content: "Latest")]
        #expect(try PromptBuilder.messages(from: history, system: "", context: 2048, output: 512).map(\.content) == ["Latest"])
        #expect(throws: (any Error).self) {
            try PromptBuilder.messages(from: [ChatMessage(role: "user", content: String(repeating: "🧠", count: 1000))], system: "", context: 2048, output: 512)
        }
    }

    @Test func parsesCodeFencesIncludingUnfinishedStreamingBlock() {
        let blocks = MarkdownParser.blocks("Hello **world**\n```swift\nlet x = 1\n```\nAfter\n```python\nprint('hi')")
        #expect(blocks.count == 4)
        #expect(blocks[1].language == "swift")
        #expect(blocks[1].text == "let x = 1")
        #expect(blocks[3].language == "python")
    }
}
