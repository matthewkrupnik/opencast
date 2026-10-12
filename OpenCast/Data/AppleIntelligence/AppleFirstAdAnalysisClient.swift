import Foundation
import OpenCastTranscription

/// Detect Ads on Apple's Private Cloud Compute first. When Apple's model
/// can't answer (device or Apple Intelligence off, usage limit, outage,
/// context overflow, or an answer that fails validation) the run falls back
/// to Gemini if a key is configured; otherwise Apple's reason is the error.
nonisolated struct AppleFirstAdAnalysisClient: EpisodeAdAnalysisClient {
    let apple: PrivateCloudComputeAdAnalysisClient
    let gemini: GeminiAdAnalysisClient
    let usesApple: Bool

    init(
        apple: PrivateCloudComputeAdAnalysisClient = PrivateCloudComputeAdAnalysisClient(),
        gemini: GeminiAdAnalysisClient,
        usesApple: Bool = Self.usesAppleForProcess
    ) {
        self.apple = apple
        self.gemini = gemini
        self.usesApple = usesApple
    }

    /// UI tests script ad detection through the Gemini key, and Apple's model
    /// would answer instead on a simulator where it is available.
    static var usesAppleForProcess: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment[GeminiConfiguration.apiKeyEnvironmentKey] != nil {
            return false
        }
        #endif
        return TranscriptIntelligenceFeatureFlags.isEnabledForProcess
    }

    /// Nil while some engine may run; Apple's own failures surface per run.
    static func unavailableMessage(configuration: GeminiConfiguration, usesApple: Bool) -> String? {
        usesApple ? nil : configuration.unavailableMessage
    }

    func analyze(_ request: EpisodeAdAnalysisAPIRequest) async throws -> EpisodeAdAnalysisSubmitOutcome {
        #if DEBUG
        if GeminiAdAnalysisClient.forcesCapRejection(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        ) {
            return try await gemini.analyze(request)
        }
        #endif
        guard usesApple else {
            return try await gemini.analyze(request)
        }

        let appleError: Error
        if let unavailable = await apple.unavailability() {
            appleError = unavailable
        } else {
            do {
                return .completed(try await apple.analyze(request))
            } catch TranscriptIntelligenceFailure.cancelled {
                throw CancellationError()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                appleError = error
            }
        }
        guard gemini.gemini.configuration.apiKey != nil else {
            throw Self.storeError(for: appleError)
        }
        return try await gemini.analyze(request)
    }

    func pollJob(id: String) async throws -> EpisodeAdAnalysisJobPollOutcome {
        try await gemini.pollJob(id: id)
    }

    /// Both engines serve the same policy, so switching never marks an
    /// analysis stale.
    func servingPolicyRevision() async throws -> String? {
        GeminiAdAnalysisClient.policyRevision
    }

    /// A usage limit defers the queue like a Gemini quota; every other Apple
    /// failure reports its own reason.
    static func storeError(for error: Error) -> Error {
        guard let failure = error as? TranscriptIntelligenceFailure else {
            return error
        }
        switch failure {
        case .cancelled:
            return CancellationError()
        case .rateLimited, .quotaLimitReached:
            return EpisodeAdAnalysisHTTPError(
                statusCode: 429,
                code: "apple_intelligence_limit_reached",
                detail: nil,
                failure: OpenCastAdAnalysisFailure(category: .capacity, retryDisposition: .afterCapacity)
            )
        case .offline:
            return EpisodeAdAnalysisHTTPError(
                statusCode: 503,
                code: "apple_intelligence_unavailable",
                detail: "You’re offline. Detect Ads needs a connection to Apple’s Private Cloud Compute."
            )
        case .notEntitled:
            return EpisodeAdAnalysisHTTPError(
                statusCode: 503,
                code: "apple_intelligence_unavailable",
                detail: "Apple Intelligence isn’t available in this build."
            )
        default:
            return EpisodeAdAnalysisHTTPError(
                statusCode: 503,
                code: "apple_intelligence_unavailable",
                detail: failure.userMessage
            )
        }
    }
}
