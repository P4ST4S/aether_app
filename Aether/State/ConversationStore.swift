import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class ConversationStore {
    private let container: ModelContainer
    let context: ModelContext
    let settings: AppSettings
    var conversations: [Conversation] = []
    var selected: Conversation?
    var draft = ""
    var isGenerating = false
    var isThinking = false
    var webStatus: String?
    var errorMessage: String?
    var persistenceError: String?
    var installedModels: [LocalModel] = []
    var connection = Connection.checking
    var focusRequest = UUID()
    var isExpanded: Bool { selected != nil }
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var generationID: UUID?
    @ObservationIgnored private var connectionID: UUID?
    @ObservationIgnored private var activeResponse: StoredMessage?
    @ObservationIgnored private var activeBuffer: ResponseBuffer?
    @ObservationIgnored private var lastCheckpoint = Date.distantPast
    @ObservationIgnored private let webRetriever: any WebRetrieving
    @ObservationIgnored private let backendFactory: @MainActor (String) throws -> any InferenceBackend

    enum Connection: Equatable {
        case checking, ready, modelMissing, unavailable(String)
        var title: String {
            switch self {
            case .checking: "Checking Ollama…"
            case .ready: "On this Mac"
            case .modelMissing: "Model setup needed"
            case .unavailable: "Ollama is offline"
            }
        }
    }

    init(context: ModelContext, settings: AppSettings,
         backendFactory: @escaping @MainActor (String) throws -> any InferenceBackend = { try OllamaClient(endpoint: $0) },
         webRetriever: any WebRetrieving = WebResearchService()) throws {
        self.container = context.container
        self.context = context
        self.settings = settings
        self.backendFactory = backendFactory
        self.webRetriever = webRetriever
        context.autosaveEnabled = false
        conversations = try context.fetch(FetchDescriptor<Conversation>(sortBy: [SortDescriptor(\Conversation.updatedAt, order: .reverse)]))
        for conversation in conversations {
            for message in conversation.messages where message.state == "streaming" {
                message.state = "stopped"
            }
        }
        try context.save()
    }

    func checkConnection() async {
        let id = UUID()
        connectionID = id
        connection = .checking
        do {
            let models = try await backendFactory(settings.endpoint).models()
            guard connectionID == id else { return }
            installedModels = models
            connection = models.contains { $0.name == settings.model } ? .ready : .modelMissing
        } catch {
            guard connectionID == id else { return }
            installedModels = []
            connection = .unavailable(error.localizedDescription)
        }
    }

    func newConversation() {
        stop()
        selected = nil
        draft = ""
        errorMessage = nil
        focusRequest = UUID()
    }

    func open(_ conversation: Conversation) {
        stop()
        selected = conversation
        draft = ""
        errorMessage = nil
        focusRequest = UUID()
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        errorMessage = nil
        let conversation: Conversation
        if let selected { conversation = selected }
        else {
            conversation = Conversation(title: String(text.prefix(60)))
            context.insert(conversation)
            conversations.insert(conversation, at: 0)
            selected = conversation
        }
        let user = StoredMessage(role: "user", content: text, position: nextPosition(in: conversation))
        user.webRequested = settings.webSearchEnabled
        conversation.messages.append(user)
        draft = ""
        startGeneration(in: conversation)
    }

    func regenerate() {
        guard !isGenerating, let conversation = selected,
              conversation.orderedMessages.contains(where: { $0.role == "user" }) else { return }
        if let last = conversation.orderedMessages.last, last.role == "assistant" {
            conversation.messages.removeAll { $0.id == last.id }
            context.delete(last)
        }
        conversation.orderedMessages.last(where: { $0.role == "user" })?.webRequested = settings.webSearchEnabled
        errorMessage = nil
        startGeneration(in: conversation)
    }

    private func startGeneration(in conversation: Conversation) {
        let response = StoredMessage(role: "assistant", position: nextPosition(in: conversation), state: "streaming", model: settings.model)
        let useWeb = conversation.orderedMessages.last(where: { $0.role == "user" })?.webRequested ?? false
        let history = conversation.orderedMessages.filter { $0.role == "user" || $0.state == "complete" }
            .map { ChatMessage(role: $0.role, content: $0.content) }
        conversation.messages.append(response)
        conversation.updatedAt = .now
        conversations.sort { $0.updatedAt > $1.updatedAt }
        save()
        let id = UUID()
        generationID = id
        activeResponse = response
        let buffer = ResponseBuffer()
        activeBuffer = buffer
        isGenerating = true
        isThinking = false
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let options = settings.options
                var sources: [WebSource] = []
                if useWeb, let question = history.last?.content {
                    webStatus = WebResearchService.urls(in: question).isEmpty ? "Searching the web…" : "Reading web pages…"
                    sources = try await webRetriever.retrieve(for: question)
                    try Task.checkCancellation()
                    guard generationID == id else { return }
                    guard !sources.isEmpty else { throw WebError.noResults }
                    // Keep citation metadata in history; downloaded page bodies are transient.
                    let references = sources.map { WebSource(id: $0.id, title: $0.title, url: $0.url, excerpt: "", kind: $0.kind, retrievedAt: $0.retrievedAt) }
                    response.webSourcesJSON = try JSONEncoder().encode(references)
                    webStatus = nil
                    save()
                }
                let runtimePrompt = settings.systemPrompt + """

                Application facts: you are Aether. Your exact local Ollama model identifier is \(settings.model). Do not guess a different model name.
                You cannot see the screen, browser tabs, local files, or control this Mac. No computer-action tools are available.
                \(sources.isEmpty ? "Web is off for this response. You have no live web evidence. Never simulate a search or pretend to have visited pages. If current web information is needed, ask the user to enable the globe button." : "Web excerpts are attached for this response. Answer from those excerpts and cite their supplied URLs.")
                """
                let messages = try PromptBuilder.messages(from: history, system: runtimePrompt,
                                                          context: options.num_ctx, output: options.num_predict, webSources: sources)
                let request = ChatRequest(model: settings.model, messages: messages, options: options,
                                          think: settings.model.lowercased().contains("qwen3") ? settings.enableThinking : nil)
                let backend = try backendFactory(settings.endpoint)
                try await backend.chat(request) { chunk in
                    try await self.receive(chunk, generation: id)
                }
                guard generationID == id else { return }
                response.content += buffer.take()
                guard !response.content.isEmpty else { throw InferenceError.emptyResponse }
                response.state = "complete"
                connection = .ready
            } catch {
                guard generationID == id else { return }
                response.content += buffer.take()
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    response.state = "stopped"
                } else {
                    response.state = "failed"
                    errorMessage = error.localizedDescription
                }
            }
            guard generationID == id else { return }
            isGenerating = false
            isThinking = false
            webStatus = nil
            generationID = nil
            generationTask = nil
            activeResponse = nil
            activeBuffer = nil
            save()
        }
    }

    private func receive(_ chunk: ChatChunk, generation: UUID) throws {
        guard generationID == generation, let response = activeResponse, let buffer = activeBuffer else { throw CancellationError() }
        try Task.checkCancellation()
        // Thinking is never persisted, sent back as context, or displayed.
        if let thought = chunk.message?.thinking, !thought.isEmpty { isThinking = true }
        if let content = chunk.message?.content, !content.isEmpty {
            isThinking = false
            buffer.append(content)
        }
        if buffer.shouldFlush || chunk.done == true {
            response.content += buffer.take()
        }
        if Date.now.timeIntervalSince(lastCheckpoint) > 1 {
            save()
            lastCheckpoint = .now
        }
        if chunk.done == true {
            response.tokenCount = chunk.eval_count
            response.tokensPerSecond = chunk.tokensPerSecond
            response.finishReason = chunk.done_reason
        }
    }

    func stop() {
        if let response = activeResponse, let buffer = activeBuffer { response.content += buffer.take() }
        activeResponse = nil
        activeBuffer = nil
        generationTask?.cancel()
        generationTask = nil
        generationID = nil
        if let message = selected?.orderedMessages.last, message.state == "streaming" {
            message.state = "stopped"
        }
        isGenerating = false
        isThinking = false
        webStatus = nil
        save()
    }

    func rename(_ conversation: Conversation, to title: String) {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        conversation.title = String(value.prefix(100))
        save()
    }

    func delete(_ conversation: Conversation) {
        if selected?.id == conversation.id { newConversation() }
        conversations.removeAll { $0.id == conversation.id }
        context.delete(conversation)
        save()
    }

    func deleteAll() {
        newConversation()
        for conversation in conversations { context.delete(conversation) }
        conversations.removeAll()
        save()
    }

    func save() {
        do { try context.save(); persistenceError = nil }
        catch { persistenceError = "History could not be saved: \(error.localizedDescription). Keep Aether open and free disk space before retrying." }
    }

    private func nextPosition(in conversation: Conversation) -> Int {
        (conversation.messages.map(\.position).max() ?? -1) + 1
    }
}

// Batch published text at approximately 25 Hz to keep rendering overhead low.
@MainActor final class ResponseBuffer {
    private var pending = ""
    private var lastFlush = Date.distantPast
    var shouldFlush: Bool { Date.now.timeIntervalSince(lastFlush) >= 0.04 }
    func append(_ text: String) { pending += text }
    func take() -> String {
        defer { pending = ""; lastFlush = .now }
        return pending
    }
}
