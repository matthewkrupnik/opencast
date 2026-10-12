import Foundation

/// Port of the worker's `retry.rs`: which upstream answers are worth another
/// attempt and how long to wait first.
nonisolated enum GeminiRetryPolicy {
    enum Decision: Equatable {
        case retry(after: TimeInterval?)
        case hardQuota
        case rejectedKey
        case doNotRetry
    }

    static let maximumRetryDelay: TimeInterval = 30

    static func classify(status: Int, retryAfter: String?, error: GeminiErrorEnvelope.Body?) -> Decision {
        switch status {
        case 500, 502, 503, 504:
            return .retry(after: retryAfter.flatMap(parseRetryAfter))
        case 429:
            return isHardQuota(error) ? .hardQuota : .retry(after: retryAfter.flatMap(parseRetryAfter))
        case 401, 403:
            return .rejectedKey
        case 400 where error?.message?.localizedCaseInsensitiveContains("api key") == true:
            // "API key not valid. Please pass a valid API key."
            return .rejectedKey
        default:
            return .doNotRetry
        }
    }

    /// 2, 4, 8, 16, then 20 seconds.
    static func backoff(attempt: Int) -> TimeInterval {
        TimeInterval(min(1 << min(attempt, 4), 20))
    }

    static func parseRetryAfter(_ value: String) -> TimeInterval? {
        guard let seconds = Int(value.trimmingCharacters(in: .whitespaces)), seconds >= 0 else {
            return nil
        }
        return min(TimeInterval(seconds), maximumRetryDelay)
    }

    private static func isHardQuota(_ error: GeminiErrorEnvelope.Body?) -> Bool {
        guard let error, error.status == "RESOURCE_EXHAUSTED" else {
            return false
        }
        let message = (error.message ?? "").lowercased()
        return ["quota", "billing", "prepay", "credit"].contains { message.contains($0) }
    }
}
