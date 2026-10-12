import Foundation

/// Failures the analysis clients translate into their own error types.
nonisolated enum GeminiCallError: Error, Equatable, Sendable {
    case apiKeyMissing
    case apiKeyRejected
    case quotaExhausted
    case httpError(status: Int)
    case retryExhausted
    case timedOut
}

/// One `models/{model}:generateContent` endpoint with the worker's transport
/// ladder: 5xx and transient 429s retry with backoff, a hard quota stops, and
/// every attempt races its own deadline.
nonisolated struct GeminiGenerateContentClient: Sendable {
    /// Long thinking calls run for minutes; the per-call deadline below is the
    /// real bound, so the session's own timeouts only catch a dead socket.
    static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 900
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    static let maximumResponseByteCount = 2 * 1_024 * 1_024

    let configuration: GeminiConfiguration
    let transport: any GeminiHTTPTransport
    var sleep: @Sendable (TimeInterval) async throws -> Void = { seconds in
        try await Task.sleep(for: .seconds(seconds))
    }

    /// Returns the 2xx response body.
    func generate(
        model: String,
        payload: Data,
        attempts: Int,
        timeout: TimeInterval
    ) async throws -> Data {
        guard let apiKey = configuration.apiKey else {
            throw GeminiCallError.apiKeyMissing
        }
        let request = makeRequest(model: model, payload: payload, apiKey: apiKey)
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            let isLastAttempt = attempt + 1 == attempts
            let delay: TimeInterval
            do {
                let (data, response) = try await send(request, timeout: timeout)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(status) {
                    guard data.count <= Self.maximumResponseByteCount else {
                        throw GeminiCallError.httpError(status: status)
                    }
                    return data
                }
                let error = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data).error
                let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
                switch GeminiRetryPolicy.classify(status: status, retryAfter: retryAfter, error: error) {
                case .hardQuota:
                    throw GeminiCallError.quotaExhausted
                case .rejectedKey:
                    throw GeminiCallError.apiKeyRejected
                case .doNotRetry:
                    throw GeminiCallError.httpError(status: status)
                case .retry(let after):
                    if isLastAttempt {
                        throw GeminiCallError.retryExhausted
                    }
                    delay = after ?? GeminiRetryPolicy.backoff(attempt: attempt + 1)
                }
            } catch let error as GeminiCallError where error != .timedOut {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
                throw CancellationError()
            } catch {
                // Transport failure or a per-call timeout: worth another try.
                if isLastAttempt {
                    throw error is GeminiCallError ? error : GeminiCallError.retryExhausted
                }
                delay = GeminiRetryPolicy.backoff(attempt: attempt + 1)
            }
            try await sleep(delay)
        }
        throw GeminiCallError.retryExhausted
    }

    private func makeRequest(model: String, payload: Data, apiKey: String) -> URLRequest {
        let url = configuration.baseURL.appending(path: "v1beta/models/\(model):generateContent")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        // Lets the key be restricted to this app in Google Cloud.
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            request.setValue(bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        return request
    }

    private func send(_ request: URLRequest, timeout: TimeInterval) async throws -> (Data, URLResponse) {
        let transport = transport
        return try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask {
                try await transport.data(for: request)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw GeminiCallError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw GeminiCallError.timedOut
            }
            return result
        }
    }
}
