import Foundation

import Testing
@testable import Aether

struct StreamDecoderTests {
    @Test func decodesContentAndThinkingSeparately() throws {
        let chunk = try #require(try StreamDecoder.decode(#"{"message":{"role":"assistant","content":"Bonjour 🌊","thinking":"private"},"done":false}"#))
        #expect(chunk.message?.content == "Bonjour 🌊")
        #expect(chunk.message?.thinking == "private")
        #expect(chunk.done == false)
    }

    @Test func decodesCompletionMetrics() throws {
        let chunk = try #require(try StreamDecoder.decode(#"{"done":true,"eval_count":24,"eval_duration":2000000000,"done_reason":"stop"}"#))
        #expect(chunk.tokensPerSecond == 12)
        #expect(chunk.done_reason == "stop")
    }

    @Test func rejectsErrorsMalformedAndEmptyObjects() {
        #expect(throws: InferenceError.server("out of memory")) {
            try StreamDecoder.decode(#"{"error":"out of memory"}"#)
        }
        #expect(throws: InferenceError.malformedStream) { try StreamDecoder.decode("not json") }
        #expect(throws: InferenceError.malformedStream) { try StreamDecoder.decode("{}") }
    }

    @Test func ignoresBlankLines() throws {
        #expect(try StreamDecoder.decode(" \r") == nil)
    }

    @Test func rejectsRemoteEndpointsAndCredentials() {
        for endpoint in ["https://example.com", "http://127.0.0.1.evil.com:11434", "http://user:pass@127.0.0.1", "http://127.0.0.1/x", "http://127.0.0.1?x=1"] {
            #expect(throws: InferenceError.invalidEndpoint) { try OllamaClient.validateEndpoint(endpoint) }
        }
    }

    @Test func acceptsLiteralLoopback() throws {
        #expect(try OllamaClient.validateEndpoint("http://127.0.0.1:11434").port == 11434)
        #expect(try OllamaClient.validateEndpoint("http://[::1]:11434").port == 11434)
    }

    @Test func filtersCloudBackedModels() throws {
        let models = try JSONDecoder().decode(ModelList.self, from: Data(#"{"models":[{"name":"local"},{"name":"qwen:cloud"},{"name":"alias","remote_model":"remote"}]}"#.utf8))
        #expect(models.models.filter(\.isLocal).map(\.name) == ["local"])
    }
    @Test func encodesFastQwenModeExplicitly() throws {
        let request = ChatRequest(model: "qwen3.5:9b-q4_K_M", messages: [ChatMessage(role: "user", content: "Hello")],
                                  options: GenerationOptions(), think: false)
        let data = try JSONEncoder().encode(request)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["think"] as? Bool == false)
        #expect(body["stream"] as? Bool == true)
    }

}
