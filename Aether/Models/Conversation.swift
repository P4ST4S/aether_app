import Foundation
import SwiftData

@Model
final class Conversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \StoredMessage.conversation) var messages: [StoredMessage]

    init(title: String = "New conversation") {
        id = UUID()
        self.title = title
        createdAt = .now
        updatedAt = .now
        messages = []
    }

    var orderedMessages: [StoredMessage] { messages.sorted { $0.position < $1.position } }
}

@Model
final class StoredMessage {
    @Attribute(.unique) var id: UUID
    var role: String
    var content: String
    var position: Int
    var state: String
    var model: String
    var createdAt: Date
    var tokenCount: Int?
    var tokensPerSecond: Double?
    var finishReason: String?
    var webRequested: Bool = false
    var webSourcesJSON: Data? = nil

    var webSources: [WebSource] {
        guard let webSourcesJSON else { return [] }
        return (try? JSONDecoder().decode([WebSource].self, from: webSourcesJSON)) ?? []
    }
    var conversation: Conversation?

    init(role: String, content: String = "", position: Int, state: String = "complete", model: String = "") {
        id = UUID()
        self.role = role
        self.content = content
        self.position = position
        self.state = state
        self.model = model
        createdAt = .now
    }
}
