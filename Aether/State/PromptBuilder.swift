import Foundation

enum PromptBuilder {
    static func messages(from history: [ChatMessage], system: String, context: Int, output: Int) throws -> [ChatMessage] {
        // UTF-8 bytes deliberately overestimate tokens; leave room for the model's chat template.
        let budget = max(0, context - output - 256)
        let systemCost = system.utf8.count + 32
        guard let latest = history.last, latest.role == "user",
              systemCost + latest.content.utf8.count + 32 <= budget else {
            throw InferenceError.server("This prompt is too large for the context budget. Shorten it or increase context length in Settings.")
        }
        var turns: [[ChatMessage]] = []
        var index = 0
        while index + 1 < history.count {
            if history[index].role == "user", history[index + 1].role == "assistant" {
                turns.append([history[index], history[index + 1]])
                index += 2
            } else { index += 1 }
        }
        var selected = [latest]
        var cost = systemCost + latest.content.utf8.count + 32
        for turn in turns.reversed() {
            let turnCost = turn.reduce(0) { $0 + $1.content.utf8.count + 32 }
            guard cost + turnCost <= budget else { break }
            selected.insert(contentsOf: turn, at: 0)
            cost += turnCost
        }
        return (system.isEmpty ? [] : [ChatMessage(role: "system", content: system)]) + selected
    }
}
