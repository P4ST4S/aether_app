import Foundation
import SwiftData
import Testing
@testable import Aether

private actor TestBackend: InferenceBackend {
    enum Behavior: Sendable { case complete, failAfterText, waitUntilCancelled, empty }
    let behavior: Behavior
    var requests: [ChatRequest] = []
    init(_ behavior: Behavior = .complete) { self.behavior = behavior }
    func models() async throws -> [LocalModel] { [LocalModel(name: "test-local")] }
    func chat(_ request: ChatRequest, onChunk: @Sendable (ChatChunk) async throws -> Void) async throws {
        requests.append(request)
        try await onChunk(ChatChunk(message: .init(role: "assistant", thinking: "private reasoning"), done: false))
        if behavior != .empty {
            try await onChunk(ChatChunk(message: .init(role: "assistant", content: "A real test fixture"), done: false))
        }
        switch behavior {
        case .failAfterText: throw InferenceError.incompleteStream
        case .waitUntilCancelled:
            try await Task.sleep(for: .seconds(30))
        case .complete, .empty: break
        }
        try await onChunk(ChatChunk(done: true, done_reason: "stop", eval_count: 4, eval_duration: 1_000_000_000))
    }
    func capturedRequests() -> [ChatRequest] { requests }
}

@MainActor struct ConversationStoreTests {
    private func makeStore(backend: TestBackend) throws -> (ConversationStore, ModelContainer) {
        let container = try ModelContainer(for: Conversation.self, StoredMessage.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
        settings.model = "test-local"
        settings.systemPrompt = "Be helpful."
        let store = try ConversationStore(context: container.mainContext, settings: settings, backendFactory: { _ in backend })
        return (store, container)
    }

    private func waitForCompletion(_ store: ConversationStore) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while store.isGenerating, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!store.isGenerating)
    }

    @Test func sendsMultiTurnWithoutThinkingAndPersists() async throws {
        let backend = TestBackend()
        let (store, container) = try makeStore(backend: backend)
        store.draft = "First question"
        store.send()
        try await waitForCompletion(store)
        #expect(store.selected?.orderedMessages.map(\.content) == ["First question", "A real test fixture"])
        #expect(store.selected?.orderedMessages.last?.state == "complete")
        store.draft = "Second question"
        store.send()
        try await waitForCompletion(store)
        let requests = await backend.capturedRequests()
        #expect(requests.count == 2)
        #expect(requests.last?.messages.map(\.role) == ["system", "user", "assistant", "user"])
        #expect(requests.last?.messages.contains { $0.content.contains("private reasoning") } == false)
        let reopened = try ConversationStore(context: ModelContext(container), settings: store.settings)
        #expect(reopened.conversations.count == 1)
        #expect(reopened.conversations.first?.messages.count == 4)
    }

    @Test func regenerateReplacesAssistantAndDoesNotDuplicateUser() async throws {
        let backend = TestBackend()
        let (store, _) = try makeStore(backend: backend)
        store.draft = "Question"
        store.send()
        try await waitForCompletion(store)
        let oldID = store.selected?.orderedMessages.last?.id
        store.regenerate()
        try await waitForCompletion(store)
        #expect(store.selected?.messages.count == 2)
        #expect(store.selected?.orderedMessages.last?.id != oldID)
        #expect(await backend.capturedRequests().last?.messages.map(\.role) == ["system", "user"])
    }

    @Test func stopPreservesPartialAndNewConversationIgnoresLateTask() async throws {
        let backend = TestBackend(.waitUntilCancelled)
        let (store, _) = try makeStore(backend: backend)
        store.draft = "Question"
        store.send()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while store.selected?.orderedMessages.last?.content.isEmpty == true, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let conversation = try #require(store.selected)
        store.stop()
        #expect(conversation.orderedMessages.last?.state == "stopped")
        #expect(conversation.orderedMessages.last?.content == "A real test fixture")
        store.newConversation()
        try await Task.sleep(for: .milliseconds(20))
        #expect(store.selected == nil)
        #expect(store.errorMessage == nil)
        #expect(!store.isGenerating)
    }

    @Test func networkFailureKeepsPartialAndExplainsRecovery() async throws {
        let (store, _) = try makeStore(backend: TestBackend(.failAfterText))
        store.draft = "Question"
        store.send()
        try await waitForCompletion(store)
        #expect(store.selected?.orderedMessages.last?.state == "failed")
        #expect(store.selected?.orderedMessages.last?.content == "A real test fixture")
        #expect(store.errorMessage == InferenceError.incompleteStream.errorDescription)
    }

    @Test func emptyResponseIsReportedAndWhitespaceDoesNothing() async throws {
        let (store, _) = try makeStore(backend: TestBackend(.empty))
        store.draft = "  \n "
        store.send()
        #expect(store.conversations.isEmpty)
        store.draft = "Question"
        store.send()
        try await waitForCompletion(store)
        #expect(store.errorMessage == InferenceError.emptyResponse.errorDescription)
    }

    @Test func renameDeleteCascadeAndReopenInterruptedHistory() async throws {
        let (store, container) = try makeStore(backend: TestBackend())
        store.draft = "Question"
        store.send()
        try await waitForCompletion(store)
        let conversation = try #require(store.selected)
        store.rename(conversation, to: "  A new title  ")
        #expect(conversation.title == "A new title")
        conversation.orderedMessages.last?.state = "streaming"
        store.save()
        let reopened = try ConversationStore(context: ModelContext(container), settings: store.settings)
        #expect(reopened.conversations.first?.orderedMessages.last?.state == "stopped")
        store.delete(conversation)
        #expect(store.conversations.isEmpty)
        #expect(store.selected == nil)
        let messages = try container.mainContext.fetch(FetchDescriptor<StoredMessage>())
        #expect(messages.isEmpty)
    }

    @Test func detectsMissingModelAndReadyModel() async throws {
        let (store, _) = try makeStore(backend: TestBackend())
        await store.checkConnection()
        #expect(store.connection == .ready)
        store.settings.model = "missing"
        await store.checkConnection()
        #expect(store.connection == .modelMissing)
    }
}
