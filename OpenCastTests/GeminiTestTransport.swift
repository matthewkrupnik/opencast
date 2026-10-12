import Foundation
@testable import OpenCast

/// Replays canned Gemini HTTP responses in order and records every request.
final class GeminiTestTransport: GeminiHTTPTransport, @unchecked Sendable {
    struct Reply {
        var status: Int
        var body: Data
        var headers: [String: String] = [:]
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private var recorded: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let reply = lock.withLock { () -> Reply? in
            recorded.append(request)
            return replies.isEmpty ? nil : replies.removeFirst()
        }
        guard let reply else {
            throw URLError(.badServerResponse)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: reply.headers
        )!
        return (reply.body, response)
    }

    /// A `generateContent` success whose single answer part is `answer`.
    static func answer(_ answer: String, finishReason: String = "STOP") -> Reply {
        let envelope: [String: Any] = [
            "candidates": [[
                "finishReason": finishReason,
                "content": ["parts": [["thought": true, "text": "thinking"], ["text": answer]]]
            ]],
            "usageMetadata": ["promptTokenCount": 10, "candidatesTokenCount": 5, "thoughtsTokenCount": 7, "totalTokenCount": 15]
        ]
        return Reply(status: 200, body: try! JSONSerialization.data(withJSONObject: envelope))
    }

    static func error(status: Int, statusText: String, message: String) -> Reply {
        let body = #"{"error":{"code":\#(status),"status":"\#(statusText)","message":"\#(message)"}}"#
        return Reply(status: status, body: Data(body.utf8))
    }

    static func requestBody(_ request: URLRequest) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] ?? [:]
    }
}

extension GeminiGenerateContentClient {
    static func testing(_ transport: GeminiTestTransport, apiKey: String? = "test-key") -> GeminiGenerateContentClient {
        GeminiGenerateContentClient(
            configuration: GeminiConfiguration(apiKey: apiKey, baseURL: URL(string: "https://gemini.test")!),
            transport: transport,
            sleep: { _ in }
        )
    }
}
