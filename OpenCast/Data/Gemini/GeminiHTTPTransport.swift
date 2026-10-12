import Foundation

nonisolated protocol GeminiHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: GeminiHTTPTransport {}
