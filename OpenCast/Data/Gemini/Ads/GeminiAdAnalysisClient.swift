import Foundation
import OpenCastTranscription

/// Promo/ad detection straight from the device to Gemini, porting the
/// worker's `promo_ad_breaks_v3` serving path: overlapping windows, strict
/// parsing, receipt validation, and one corrective repair per window. Every
/// run completes synchronously, so `pollJob` reports the job gone and the
/// store's resume path re-runs `analyze` after an interrupted launch.
nonisolated struct GeminiAdAnalysisClient: EpisodeAdAnalysisClient {
    static let policyRevision = "ios-2026-10-12.1"
    static let initialAttempts = 2
    static let repairAttempts = 1
    static let callTimeout: TimeInterval = 120

    let gemini: GeminiGenerateContentClient

    init(
        configuration: GeminiConfiguration = .current,
        transport: any GeminiHTTPTransport = GeminiGenerateContentClient.sharedSession
    ) {
        gemini = GeminiGenerateContentClient(configuration: configuration, transport: transport)
    }

    init(gemini: GeminiGenerateContentClient) {
        self.gemini = gemini
    }

    func analyze(_ request: EpisodeAdAnalysisAPIRequest) async throws -> EpisodeAdAnalysisSubmitOutcome {
        #if DEBUG
        if Self.forcesCapRejection(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        ) {
            throw EpisodeAdAnalysisHTTPError(
                statusCode: 429,
                code: "daily_request_cap_exceeded",
                detail: "Forced by OPENCAST_ADANALYSIS_FORCE_CAP"
            )
        }
        #endif
        guard gemini.configuration.apiKey != nil else {
            throw EpisodeAdAnalysisError.apiKeyMissing
        }
        guard !request.segments.isEmpty else {
            throw EpisodeAdAnalysisHTTPError(statusCode: 400, code: "empty_transcript", detail: nil)
        }
        let windows = AdAnalysisV3Windowing.windows(request)
        let single = windows.count == 1
        let outcomes = try await GeminiBackgroundAssertion.run(named: "Detect Ads") {
            try await analyzeWindows(windows, single: single)
        }

        var output = AdAnalysisV3Output(spans: [])
        var usage: EpisodeAdAnalysisAPIUsage?
        var notices: [String] = []
        for outcome in outcomes {
            output.spans += outcome.output.spans
            usage = Self.combine(usage, outcome.usage)
            notices += outcome.notices
        }
        // Multi-window global alarms have no isolated corrective scope: stop
        // with evidence intact rather than publish a subset.
        let validated = AdAnalysisV3Validator.validate(request, output)
        guard validated.isComplete else {
            throw Self.incomplete()
        }
        notices = Array(Set(notices + validated.notices)).sorted()
        return .completed(EpisodeAdAnalysisAPIResponse(
            schemaVersion: 1,
            requestID: request.requestID,
            model: AdAnalysisV3Payload.model,
            policy: AdAnalysisV3Payload.policy,
            policyRevision: Self.policyRevision,
            spans: validated.spans,
            warnings: notices,
            usage: usage
        ))
    }

    func pollJob(id: String) async throws -> EpisodeAdAnalysisJobPollOutcome {
        throw EpisodeAdAnalysisHTTPError(statusCode: 404, code: "job_not_found", detail: nil)
    }

    func servingPolicyRevision() async throws -> String? {
        Self.policyRevision
    }

    #if DEBUG
    static func forcesCapRejection(environment: [String: String], arguments: [String]) -> Bool {
        environment["OPENCAST_ADANALYSIS_FORCE_CAP"] == "1"
            || arguments.contains("-OPENCAST_ADANALYSIS_FORCE_CAP")
    }
    #endif

    private struct WindowOutcome: Sendable {
        var index: Int
        var output: AdAnalysisV3Output
        var usage: GeminiResponse.UsageMetadata?
        var notices: [String]
    }

    /// At most four windows in flight; the first failure cancels the rest.
    private func analyzeWindows(
        _ windows: [EpisodeAdAnalysisAPIRequest],
        single: Bool
    ) async throws -> [WindowOutcome] {
        try await withThrowingTaskGroup(of: WindowOutcome.self) { group in
            var pending = windows.enumerated().makeIterator()
            for _ in 0..<AdAnalysisV3Windowing.concurrentWindows {
                guard let (index, window) = pending.next() else {
                    break
                }
                group.addTask { try await analyzeWindow(index: index, window: window, single: single) }
            }
            var outcomes: [WindowOutcome] = []
            while let outcome = try await group.next() {
                outcomes.append(outcome)
                if let (index, window) = pending.next() {
                    group.addTask { try await analyzeWindow(index: index, window: window, single: single) }
                }
            }
            return outcomes.sorted { $0.index < $1.index }
        }
    }

    private func analyzeWindow(
        index: Int,
        window: EpisodeAdAnalysisAPIRequest,
        single: Bool
    ) async throws -> WindowOutcome {
        func validate(_ output: AdAnalysisV3Output) -> AdAnalysisV3Validator.Validation {
            single ? AdAnalysisV3Validator.validate(window, output) : AdAnalysisV3Validator.validateWindow(window, output)
        }

        let payload = try AdAnalysisV3Payload.payload(window)
        let first = try await call(payload, attempts: Self.initialAttempts)
        let validation = first.output.map(validate)
            ?? AdAnalysisV3Validator.Validation(issues: [first.issue ?? "v3_missing_output"])
        if validation.isComplete, let output = first.output {
            return WindowOutcome(index: index, output: output, usage: first.usage, notices: validation.notices)
        }

        let corrective: [String: Any]
        do {
            corrective = try AdAnalysisV3Payload.repairPayload(
                payload,
                request: window,
                previous: first.output,
                issues: validation.issues
            )
        } catch {
            throw EpisodeAdAnalysisHTTPError(statusCode: 422, code: "repair_feedback_exceeded", detail: nil)
        }
        let repaired = try await call(corrective, attempts: Self.repairAttempts)
        guard let output = repaired.output else {
            throw Self.incomplete()
        }
        var checked = validate(output)
        if !AdAnalysisV3Validator.preservesVerifiedBreaks(before: validation, after: checked) {
            checked.issues.append("v3_repair_lost_candidate")
        }
        guard checked.isComplete else {
            throw Self.incomplete()
        }
        return WindowOutcome(
            index: index,
            output: output,
            usage: Self.sum(first.usage, repaired.usage),
            notices: checked.notices + ["v3_semantic_repair"]
        )
    }

    private struct Parsed: Sendable {
        var output: AdAnalysisV3Output?
        var usage: GeminiResponse.UsageMetadata?
        var issue: String?
    }

    private func call(_ payload: [String: Any], attempts: Int) async throws -> Parsed {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
        let body: Data
        do {
            body = try await gemini.generate(
                model: AdAnalysisV3Payload.model,
                payload: data,
                attempts: attempts,
                timeout: Self.callTimeout
            )
        } catch let error as GeminiCallError {
            throw Self.httpError(for: error)
        }
        guard let response = try? JSONDecoder().decode(GeminiResponse.self, from: body) else {
            return Parsed(issue: "v3_malformed_response")
        }
        switch response.strictAnswerText() {
        case .failure(let issue):
            return Parsed(usage: response.usageMetadata, issue: "v3_" + issue.rawValue)
        case .success(let text):
            guard let output = try? JSONDecoder().decode(AdAnalysisV3Output.self, from: Data(text.utf8)) else {
                return Parsed(usage: response.usageMetadata, issue: "v3_malformed_model_json")
            }
            return Parsed(output: output, usage: response.usageMetadata)
        }
    }

    static func incomplete() -> EpisodeAdAnalysisHTTPError {
        EpisodeAdAnalysisHTTPError(
            statusCode: 422,
            code: "ad_analysis_incomplete",
            detail: nil,
            failure: OpenCastAdAnalysisFailure(
                category: .validationExhausted,
                retryDisposition: .explicitRetry,
                policyRevision: policyRevision
            )
        )
    }

    static func httpError(for error: GeminiCallError) -> Error {
        switch error {
        case .apiKeyMissing:
            EpisodeAdAnalysisError.apiKeyMissing
        case .apiKeyRejected:
            EpisodeAdAnalysisHTTPError(statusCode: 401, code: "gemini_api_key_rejected", detail: nil)
        case .quotaExhausted:
            EpisodeAdAnalysisHTTPError(
                statusCode: 429,
                code: "gemini_quota_exhausted",
                detail: nil,
                failure: OpenCastAdAnalysisFailure(category: .capacity, retryDisposition: .afterCapacity)
            )
        case .httpError(let status):
            EpisodeAdAnalysisHTTPError(statusCode: 502, code: "gemini_http_error", detail: "HTTP \(status)")
        case .retryExhausted, .timedOut:
            EpisodeAdAnalysisHTTPError(
                statusCode: 503,
                code: "gemini_retry_exhausted",
                detail: nil,
                failure: OpenCastAdAnalysisFailure(category: .transientTransport, retryDisposition: .boundedRetry)
            )
        }
    }

    private static func sum(
        _ lhs: GeminiResponse.UsageMetadata?,
        _ rhs: GeminiResponse.UsageMetadata?
    ) -> GeminiResponse.UsageMetadata? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return GeminiResponse.UsageMetadata(
            promptTokenCount: (lhs.promptTokenCount ?? 0) + (rhs.promptTokenCount ?? 0),
            candidatesTokenCount: (lhs.candidatesTokenCount ?? 0) + (rhs.candidatesTokenCount ?? 0),
            thoughtsTokenCount: (lhs.thoughtsTokenCount ?? 0) + (rhs.thoughtsTokenCount ?? 0),
            totalTokenCount: lhs.total + rhs.total
        )
    }

    private static func combine(
        _ usage: EpisodeAdAnalysisAPIUsage?,
        _ metadata: GeminiResponse.UsageMetadata?
    ) -> EpisodeAdAnalysisAPIUsage? {
        guard let metadata else {
            return usage
        }
        let prompt = (usage?.promptTokenCount ?? 0) + (metadata.promptTokenCount ?? 0)
        // Thinking tokens bill as output.
        let candidates = (usage?.candidatesTokenCount ?? 0)
            + (metadata.candidatesTokenCount ?? 0) + (metadata.thoughtsTokenCount ?? 0)
        return EpisodeAdAnalysisAPIUsage(
            promptTokenCount: prompt,
            candidatesTokenCount: candidates,
            totalTokenCount: (usage?.totalTokenCount ?? 0) + metadata.total
        )
    }
}
