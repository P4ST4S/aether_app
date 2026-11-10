import Foundation

struct ChatMessage: Codable, Sendable, Equatable {
    let role: String
    let content: String
}

struct ChatRequest: Encodable, Sendable {
    let model: String
    let messages: [ChatMessage]
    var stream = true
    var keep_alive = "5m"
    let options: GenerationOptions
    var think: Bool? = nil
}

struct GenerationOptions: Codable, Sendable {
    var num_ctx: Int = 8192
    var temperature: Double = 0.6
    var num_predict: Int = 2048
}

struct ChatChunk: Decodable, Sendable {
    struct Message: Decodable, Sendable {
        var role: String?
        var content: String?
        var thinking: String?
    }
    var message: Message?
    var done: Bool?
    var done_reason: String?
    var error: String?
    var eval_count: Int?
    var eval_duration: Double?
    var prompt_eval_count: Int?
    var total_duration: Double?

    var tokensPerSecond: Double? {
        guard let count = eval_count, let duration = eval_duration, duration > 0 else { return nil }
        return Double(count) / (duration / 1_000_000_000)
    }
}

struct LocalModel: Decodable, Sendable, Identifiable {
    var name: String
    var size: Int64?
    var remote_model: String?
    var remote_host: String?
    var id: String { name }
    var isLocal: Bool {
        remote_model == nil && remote_host == nil && !Self.isCloudName(name)
    }
    static func isCloudName(_ name: String) -> Bool {
        name.lowercased().contains("cloud")
    }
}

struct ModelList: Decodable, Sendable {
    let models: [LocalModel]
}

enum InferenceError: LocalizedError, Equatable {
    case invalidEndpoint, remoteModel, http(Int, String), server(String), malformedStream, incompleteStream, emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Use an HTTP endpoint on 127.0.0.1 or [::1], with no path, credentials, or query. Inference stays on this Mac."
        case .remoteModel: "Cloud-backed models are disabled. Select a locally installed model."
        case let .http(code, message): "Ollama returned HTTP \(code). \(message)"
        case let .server(message): message
        case .malformedStream: "Ollama sent an invalid streaming response. Retry or update Ollama."
        case .incompleteStream: "The connection ended before Ollama finished. Your partial response is preserved."
        case .emptyResponse: "The model finished without a text response. Try regenerating or changing the model."
        }
    }
}

enum StreamDecoder {
    static func decode(_ line: String) throws -> ChatChunk? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard line.utf8.count <= 2_000_000, let data = line.data(using: .utf8) else {
            throw InferenceError.malformedStream
        }
        let chunk: ChatChunk
        do { chunk = try JSONDecoder().decode(ChatChunk.self, from: data) }
        catch { throw InferenceError.malformedStream }
        if let error = chunk.error { throw InferenceError.server(error) }
        guard chunk.message != nil || chunk.done == true else { throw InferenceError.malformedStream }
        return chunk
    }
}
