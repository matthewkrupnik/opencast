import Foundation

struct EpisodeTranscriptAnalysisHTTPError: LocalizedError, Sendable, Equatable {
    /// Worker cap-rejection codes (`Server/TranscriptAnalysisWorker`): all
    /// three defer identically — the client queues and retries later, never
    /// surfaces a failure (caps are an abuse ceiling, not the access model).
    /// Classification is status + code — never the user-facing message string.
    static let capExceededCodes: Set<String> = [
        "daily_request_cap_exceeded",
        "daily_input_token_cap_exceeded",
        "global_capacity_exhausted",
        "gemini_quota_exhausted"
    ]
    static let transientJobFailureCodes: Set<String> = [
        "job_failed_transient",
        "job_not_found"
    ]
    static let jobUnavailableCode = "job_unavailable"
    static let transientServerStatusCodes: Set<Int> = [500, 502, 503, 504]

    var statusCode: Int
    var code: String
    var detail: String?

    var isCapExceeded: Bool {
        statusCode == 429 && Self.capExceededCodes.contains(code)
    }

    var isTransientJobFailure: Bool {
        Self.transientJobFailureCodes.contains(code)
    }

    /// A read of an accepted job that failed without a verdict: an
    /// unavailable job object or a 5xx with no JSON body (the client's
    /// synthesized `http_<status>` code). The poller retries the same
    /// handle; every coded worker error stays terminal.
    var isTransientPollFailure: Bool {
        code == Self.jobUnavailableCode
            || code.hasPrefix("http_") && Self.transientServerStatusCodes.contains(statusCode)
    }

    var errorDescription: String? {
        switch code {
        case "global_capacity_exhausted":
            return "Chapters & Summary is at capacity today. It will retry tomorrow."
        case "daily_request_cap_exceeded", "daily_input_token_cap_exceeded":
            return "Chapters & Summary has reached today’s device limit. It will retry tomorrow."
        case "gemini_quota_exhausted":
            return "Gemini quota for this API key is exhausted. It will retry later."
        case "gemini_api_key_rejected":
            return "Gemini rejected the configured API key."
        default:
            break
        }

        if let detail, !detail.isEmpty {
            return "Chapters & Summary failed (\(code)): \(detail)"
        }
        return "Chapters & Summary failed (\(code))."
    }
}
