import Foundation

/// Chapters & Summary straight from the device to Gemini, porting the
/// worker's `transcript_analysis_v2` serving path. Every run completes
/// synchronously, so `pollJob` reports the job gone and the store's resume
/// path re-runs `analyze` after an interrupted launch.
nonisolated struct GeminiTranscriptAnalysisClient: EpisodeTranscriptAnalysisClient {
    static let maximumAttempts = 3
    static let mediumCallTimeout: TimeInterval = 120
    static let highCallTimeout: TimeInterval = 300
    static let runBudget: TimeInterval = 540

    let gemini: GeminiGenerateContentClient
    var now: @Sendable () -> Date = { .now }

    init(
        configuration: GeminiConfiguration = .current,
        transport: any GeminiHTTPTransport = GeminiGenerateContentClient.sharedSession
    ) {
        gemini = GeminiGenerateContentClient(configuration: configuration, transport: transport)
    }

    init(gemini: GeminiGenerateContentClient) {
        self.gemini = gemini
    }

    func analyze(_ request: EpisodeTranscriptAnalysisAPIRequest) async throws -> EpisodeTranscriptAnalysisSubmitOutcome {
        guard gemini.configuration.apiKey != nil else {
            throw EpisodeTranscriptAnalysisError.apiKeyMissing
        }
        guard !request.segments.isEmpty else {
            throw EpisodeTranscriptAnalysisHTTPError(statusCode: 400, code: "empty_transcript", detail: nil)
        }
        let prepared: TranscriptAnalysisCoalescer.Prepared
        do {
            prepared = try TranscriptAnalysisCoalescer.prepare(request.segments)
        } catch {
            throw EpisodeTranscriptAnalysisHTTPError(statusCode: 422, code: "transcript_too_dense", detail: nil)
        }
        let prompt = TranscriptAnalysisV2Prompt.build(request, segments: prepared.segments)
        let deadline = now().addingTimeInterval(Self.runBudget)
        var warnings: [String] = []
        var usage: EpisodeTranscriptAnalysisAPIUsage?
        var lastViolations: [String] = []

        for attempt in 0..<Self.maximumAttempts {
            let thinking = attempt == 0
                ? TranscriptAnalysisV2Prompt.thinkingLevel(forSegmentCount: prepared.segments.count)
                : "high"
            let remaining = deadline.timeIntervalSince(now())
            guard remaining > 1 else {
                break
            }
            let timeout = min(thinking == "high" ? Self.highCallTimeout : Self.mediumCallTimeout, remaining)
            let body: Data
            do {
                body = try await GeminiBackgroundAssertion.run(named: "Chapters & Summary") {
                    try await gemini.generate(
                        model: TranscriptAnalysisV2Prompt.model,
                        payload: try TranscriptAnalysisV2Prompt.payload(prompt: prompt, thinkingLevel: thinking),
                        attempts: 3,
                        timeout: timeout
                    )
                }
            } catch let error as GeminiCallError {
                throw Self.httpError(for: error)
            }
            let response = try? JSONDecoder().decode(GeminiResponse.self, from: body)
            usage = Self.combine(usage, response?.usageMetadata)
            let violations: [String]
            switch response.map({ $0.lenientAnswerText() }) {
            case .success(let answer)?:
                if let warning = answer.warning {
                    warnings.append(warning)
                }
                if let output = try? JSONDecoder().decode(
                    TranscriptAnalysisV2Validator.ModelOutput.self,
                    from: Data(answer.text.utf8)
                ) {
                    switch TranscriptAnalysisV2Validator.validate(
                        output,
                        segments: request.segments,
                        prepared: prepared,
                        audioDuration: request.transcript.audioDuration
                    ) {
                    case .success(let validated):
                        return .completed(EpisodeTranscriptAnalysisAPIResponse(
                            schemaVersion: 1,
                            requestID: request.requestID,
                            model: TranscriptAnalysisV2Prompt.model,
                            policy: TranscriptAnalysisV2Prompt.policy,
                            chapters: validated.chapters,
                            summary: validated.summary,
                            warnings: warnings + validated.warnings,
                            usage: usage
                        ))
                    case .failure(let hard):
                        violations = hard.messages
                    }
                } else {
                    violations = [GeminiParseIssue.malformedModelJSON.rawValue]
                }
            case .failure(let issue)?:
                violations = [issue.rawValue]
            case nil:
                violations = [GeminiParseIssue.malformedResponse.rawValue]
            }
            lastViolations = violations
            if attempt + 1 < Self.maximumAttempts {
                let codes = Set(violations.map { $0.split(separator: ":").first.map(String.init) ?? $0 })
                warnings.append("invalid_model_output_retried_high:\(codes.sorted().joined(separator: ","))")
            }
        }
        throw EpisodeTranscriptAnalysisHTTPError(
            statusCode: 502,
            code: "invalid_model_output",
            detail: lastViolations.prefix(3).joined(separator: "; ")
        )
    }

    func pollJob(id: String) async throws -> EpisodeTranscriptAnalysisJobPollOutcome {
        throw EpisodeTranscriptAnalysisHTTPError(statusCode: 404, code: "job_not_found", detail: nil)
    }

    static func httpError(for error: GeminiCallError) -> Error {
        switch error {
        case .apiKeyMissing:
            EpisodeTranscriptAnalysisError.apiKeyMissing
        case .apiKeyRejected:
            EpisodeTranscriptAnalysisHTTPError(statusCode: 401, code: "gemini_api_key_rejected", detail: nil)
        case .quotaExhausted:
            EpisodeTranscriptAnalysisHTTPError(statusCode: 429, code: "gemini_quota_exhausted", detail: nil)
        case .httpError(let status):
            EpisodeTranscriptAnalysisHTTPError(statusCode: 502, code: "gemini_http_error", detail: "HTTP \(status)")
        case .retryExhausted, .timedOut:
            EpisodeTranscriptAnalysisHTTPError(statusCode: 503, code: "gemini_retry_exhausted", detail: nil)
        }
    }

    private static func combine(
        _ usage: EpisodeTranscriptAnalysisAPIUsage?,
        _ metadata: GeminiResponse.UsageMetadata?
    ) -> EpisodeTranscriptAnalysisAPIUsage? {
        guard let metadata else {
            return usage
        }
        let next = EpisodeTranscriptAnalysisAPIUsage(
            promptTokenCount: metadata.promptTokenCount ?? 0,
            candidatesTokenCount: metadata.candidatesTokenCount ?? 0,
            thoughtsTokenCount: metadata.thoughtsTokenCount ?? 0,
            totalTokenCount: metadata.total
        )
        guard let usage else {
            return next
        }
        return EpisodeTranscriptAnalysisAPIUsage(
            promptTokenCount: usage.promptTokenCount + next.promptTokenCount,
            candidatesTokenCount: usage.candidatesTokenCount + next.candidatesTokenCount,
            thoughtsTokenCount: usage.thoughtsTokenCount + next.thoughtsTokenCount,
            totalTokenCount: usage.totalTokenCount + next.totalTokenCount
        )
    }
}
