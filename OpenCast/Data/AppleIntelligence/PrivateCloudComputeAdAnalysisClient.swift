import Foundation

/// Promo/ad detection on Apple's Private Cloud Compute model, with the same
/// `promo_ad_breaks_v3` prompt, receipt validation, and single repair turn
/// as the Gemini client. Windows run one at a time to stay inside Apple's
/// rate limits, and shrink when the model reports its context exceeded.
nonisolated struct PrivateCloudComputeAdAnalysisClient: Sendable {
    static let model = "apple-private-cloud-compute"
    /// Tried in order; the next size is used only after a context overflow.
    static let windowSizes = [800, 400, 200]
    static let callDeadline: Duration = .seconds(120)

    let makeModelClient: @MainActor @Sendable () -> any TranscriptIntelligenceModelClient
    let crashBreaker: AppleAdAnalysisCrashBreaker

    init(
        makeModelClient: @escaping @MainActor @Sendable () -> any TranscriptIntelligenceModelClient = {
            PrivateCloudComputeTranscriptIntelligenceClient()
        },
        crashBreaker: AppleAdAnalysisCrashBreaker = AppleAdAnalysisCrashBreaker()
    ) {
        self.makeModelClient = makeModelClient
        self.crashBreaker = crashBreaker
    }

    /// Why a run can't start right now, or nil when the model is ready.
    @MainActor
    func unavailability() -> Error? {
        if crashBreaker.suspension() != nil {
            return EpisodeAdAnalysisHTTPError(
                statusCode: 503,
                code: "apple_intelligence_unavailable",
                detail: "Apple Intelligence stopped unexpectedly during the last run. Detect Ads will try it again later."
            )
        }
        let client = makeModelClient()
        let reason: String? = switch client.modelAvailability {
        case .available:
            nil
        case .deviceNotEligible:
            "This device can’t use Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in Settings to detect ads."
        case .systemNotReady:
            "Apple Intelligence isn’t ready yet. Try again later."
        }
        if let reason {
            return EpisodeAdAnalysisHTTPError(statusCode: 503, code: "apple_intelligence_unavailable", detail: reason)
        }
        let quota = client.quota
        guard !quota.isLimitReached else {
            return TranscriptIntelligenceFailure.quotaLimitReached(resetDate: quota.resetDate)
        }
        return nil
    }

    /// Throws `TranscriptIntelligenceFailure` when Apple's model can't answer,
    /// and `EpisodeAdAnalysisHTTPError` when its answer fails validation.
    func analyze(_ request: EpisodeAdAnalysisAPIRequest) async throws -> EpisodeAdAnalysisAPIResponse {
        crashBreaker.begin()
        defer { crashBreaker.end() }
        return try await GeminiBackgroundAssertion.run(named: "Detect Ads") {
            try await run(request)
        }
    }

    @MainActor
    private func run(_ request: EpisodeAdAnalysisAPIRequest) async throws -> EpisodeAdAnalysisAPIResponse {
        let client = makeModelClient()
        var overflow: Error?
        for size in Self.windowSizes {
            do {
                return try await run(request, windowSize: size, client: client)
            } catch let failure as TranscriptIntelligenceFailure {
                guard case .contextSizeExceeded = failure else {
                    throw failure
                }
                overflow = failure
            }
        }
        throw overflow ?? TranscriptIntelligenceFailure.contextSizeExceeded(tokenCount: 0, contextSize: 0)
    }

    @MainActor
    private func run(
        _ request: EpisodeAdAnalysisAPIRequest,
        windowSize: Int,
        client: any TranscriptIntelligenceModelClient
    ) async throws -> EpisodeAdAnalysisAPIResponse {
        let windows = AdAnalysisV3Windowing.windows(request, size: windowSize, overlap: windowSize * 3 / 20)
        let single = windows.count == 1
        var output = AdAnalysisV3Output(spans: [])
        var usage = TranscriptIntelligenceUsage()
        var notices: [String] = []
        for window in windows {
            let outcome = try await analyzeWindow(window, single: single, client: client)
            output.spans += outcome.output.spans
            usage.inputTokens += outcome.usage.inputTokens
            usage.outputTokens += outcome.usage.outputTokens
            notices += outcome.notices
        }

        let validated = AdAnalysisV3Validator.validate(request, output)
        guard validated.isComplete else {
            throw GeminiAdAnalysisClient.incomplete()
        }
        return EpisodeAdAnalysisAPIResponse(
            schemaVersion: 1,
            requestID: request.requestID,
            model: Self.model,
            policy: AdAnalysisV3Payload.policy,
            policyRevision: GeminiAdAnalysisClient.policyRevision,
            spans: validated.spans,
            warnings: Array(Set(notices + validated.notices)).sorted(),
            usage: EpisodeAdAnalysisAPIUsage(
                promptTokenCount: usage.inputTokens,
                candidatesTokenCount: usage.outputTokens,
                totalTokenCount: usage.inputTokens + usage.outputTokens
            )
        )
    }

    private struct WindowOutcome {
        var output: AdAnalysisV3Output
        var usage: TranscriptIntelligenceUsage
        var notices: [String]
    }

    /// One session per window: the first answer, then at most one repair
    /// turn in the same session, which already holds that answer.
    @MainActor
    private func analyzeWindow(
        _ window: EpisodeAdAnalysisAPIRequest,
        single: Bool,
        client: any TranscriptIntelligenceModelClient
    ) async throws -> WindowOutcome {
        func validate(_ output: AdAnalysisV3Output) -> AdAnalysisV3Validator.Validation {
            single ? AdAnalysisV3Validator.validate(window, output) : AdAnalysisV3Validator.validateWindow(window, output)
        }

        let session = client.makeSession(instructions: AdAnalysisV3Payload.instructions, tools: [])
        let first = try await respond(session, to: try AdAnalysisV3Payload.input(window))
        let validation = first.output.map(validate)
            ?? AdAnalysisV3Validator.Validation(issues: ["v3_malformed_model_json"])
        if validation.isComplete, let output = first.output {
            return WindowOutcome(output: output, usage: first.usage, notices: validation.notices)
        }

        let feedback: String
        do {
            feedback = try AdAnalysisV3Payload.repairFeedback(
                request: window,
                previous: first.output,
                issues: validation.issues
            )
        } catch {
            throw EpisodeAdAnalysisHTTPError(statusCode: 422, code: "repair_feedback_exceeded", detail: nil)
        }
        let repaired = try await respond(session, to: feedback)
        guard let output = repaired.output else {
            throw GeminiAdAnalysisClient.incomplete()
        }
        var checked = validate(output)
        if !AdAnalysisV3Validator.preservesVerifiedBreaks(before: validation, after: checked) {
            checked.issues.append("v3_repair_lost_candidate")
        }
        guard checked.isComplete else {
            throw GeminiAdAnalysisClient.incomplete()
        }
        return WindowOutcome(
            output: output,
            usage: TranscriptIntelligenceUsage(
                inputTokens: first.usage.inputTokens + repaired.usage.inputTokens,
                outputTokens: first.usage.outputTokens + repaired.usage.outputTokens
            ),
            notices: checked.notices + ["v3_semantic_repair"]
        )
    }

    /// A malformed answer is a repairable issue, not a failure.
    @MainActor
    private func respond(
        _ session: any TranscriptIntelligenceSession,
        to prompt: String
    ) async throws -> (output: AdAnalysisV3Output?, usage: TranscriptIntelligenceUsage) {
        let options = TranscriptIntelligenceGenerationOptions(toolCalling: .disallowed)
        do {
            let response = try await TranscriptIntelligenceRequestDeadline.run(Self.callDeadline) {
                try await session.respond(to: prompt, generating: AppleAdAnalysisAnswer.self, options: options)
            }
            return (response.content.output, response.usage)
        } catch TranscriptIntelligenceFailure.malformedOutput {
            return (nil, TranscriptIntelligenceUsage())
        }
    }
}
