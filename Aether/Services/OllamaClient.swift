import Foundation

protocol InferenceBackend: Sendable {
    func models() async throws -> [LocalModel]
    func chat(_ request: ChatRequest, onChunk: @Sendable (ChatChunk) async throws -> Void) async throws
}

private final class LocalSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        // A local server must never redirect conversation data to another host.
        nil
    }
}

struct OllamaClient: InferenceBackend {
    let endpoint: URL
    private let session: URLSession

    init(endpoint: String) throws {
        self.endpoint = try Self.validateEndpoint(endpoint)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 1800
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.connectionProxyDictionary = [:]
        session = URLSession(configuration: configuration, delegate: LocalSessionDelegate(), delegateQueue: nil)
    }

    static func validateEndpoint(_ value: String) throws -> URL {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "http", let host = url.host,
              ["127.0.0.1", "[::1]", "::1"].contains(host),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { throw InferenceError.invalidEndpoint }
        return url
    }

    func models() async throws -> [LocalModel] {
        var request = URLRequest(url: endpoint.appending(path: "api/tags"))
        request.timeoutInterval = 5
        let (data, response) = try await session.data(for: request)
        try Self.validate(response, errorBody: String(decoding: data.prefix(1024), as: UTF8.self))
        return try JSONDecoder().decode(ModelList.self, from: data).models.filter(\.isLocal).sorted { $0.name < $1.name }
    }

    func chat(_ request: ChatRequest, onChunk: @Sendable (ChatChunk) async throws -> Void) async throws {
        guard !LocalModel.isCloudName(request.model) else { throw InferenceError.remoteModel }
        // Refresh metadata immediately before every inference, including after settings changes.
        guard try await models().contains(where: { $0.name == request.model }) else {
            throw InferenceError.server("The selected local model is missing. Refresh models in Settings.")
        }
        var urlRequest = URLRequest(url: endpoint.appending(path: "api/chat"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw InferenceError.malformedStream }
        if !(200..<300).contains(http.statusCode) {
            var body = ""
            for try await byte in bytes {
                body.append(Character(UnicodeScalar(byte)))
                if body.utf8.count >= 1024 { break }
            }
            throw InferenceError.http(http.statusCode, body)
        }
        var completed = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let chunk = try StreamDecoder.decode(line) else { continue }
            try await onChunk(chunk)
            if chunk.done == true { completed = true; break }
        }
        try Task.checkCancellation()
        guard completed else { throw InferenceError.incompleteStream }
    }

    private static func validate(_ response: URLResponse, errorBody: String) throws {
        guard let http = response as? HTTPURLResponse else { throw InferenceError.malformedStream }
        guard (200..<300).contains(http.statusCode) else { throw InferenceError.http(http.statusCode, errorBody) }
    }
}
