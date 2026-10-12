import Foundation
import OpenCastTranscription

/// Product engine resolution: Apple Speech whenever the device
/// and the podcast's locale support it — installing assets on demand — with
/// Whisper large-v3 as the automatic fallback. Explicit DEBUG overrides stay
/// engine-strict.
struct EpisodeTranscriptionPlanResolver {
    static let fallbackLanguageCode = "en-US"
    static let whisperRunLanguageCode = "en"

    let transcriptionModels: TranscriptionModelStore
    let appleSpeechAssets: AppleSpeechAssetStore
    /// Armed pass drains run under a
    /// continued-processing task the system may revoke at any time — no
    /// documented budget, no background resubmission (DTS-confirmed). Apple
    /// Speech restarts from zero after revocation, so on devices without
    /// background GPU an armed pass could lose the whole transcript every
    /// revocation. Callers on that path set this to prefer Whisper,
    /// whose window checkpoints survive revocation.
    var prefersRevocationDurableEngine = false

    /// Throws `EpisodeTranscriptionError.missingSpeechModel` when the
    /// resolution lands on whisper and no model is installed — callers route
    /// that into the existing model-consent/install flow and re-resolve.
    func resolve(
        requestedEngine: AdFreePassTranscriptionEngine,
        podcastLanguageCode: String?
    ) async throws -> EpisodeTranscriptionPlan {
        switch requestedEngine {
        case .productDefault:
            return try await resolveProductDefault(podcastLanguageCode: podcastLanguageCode)
        case .selectedWhisperModel:
            guard let modelSummary = transcriptionModels.installedSummary else {
                throw EpisodeTranscriptionError.missingSpeechModel
            }
            return whisperPlan(
                summary: modelSummary,
                languageCode: Self.whisperRunLanguageCode,
                isEngineStrict: true
            )
        case .appleSpeech:
            return try await strictApplePlan(podcastLanguageCode: podcastLanguageCode)
        }
    }

    private func resolveProductDefault(
        podcastLanguageCode: String?
    ) async throws -> EpisodeTranscriptionPlan {
        let languageCode = podcastLanguageCode ?? Self.fallbackLanguageCode

        if prefersRevocationDurableEngine {
            guard let whisperSummary = try? transcriptionModels.installedModelSummary() else {
                // Routes into the existing model-consent/install stage.
                throw EpisodeTranscriptionError.missingSpeechModel
            }
            AdFreePassBackgroundRunLog.record(
                "engine resolution durable whisper language=\(languageCode)"
            )
            return whisperPlan(
                summary: whisperSummary,
                languageCode: languageCode,
                isEngineStrict: false
            )
        }

        if appleSpeechAssets.isTranscriberAvailable {
            do {
                let localeIdentifier = try await appleSpeechAssets.ensureInstalledAssets(
                    forLanguageCode: languageCode
                )
                return applePlan(
                    localeIdentifier: localeIdentifier,
                    languageCode: languageCode,
                    isEngineStrict: false
                )
            } catch {
                AdFreePassBackgroundRunLog.record(
                    "engine resolution apple failed language=\(languageCode) fallback=whisper error=\(error.localizedDescription)"
                )
            }
        } else {
            AdFreePassBackgroundRunLog.record(
                "engine resolution apple transcriber unavailable fallback=whisper"
            )
        }

        guard let whisperSummary = try? transcriptionModels.installedModelSummary() else {
            throw EpisodeTranscriptionError.missingSpeechModel
        }

        // Fallback documents keep the honest podcast language while Whisper
        // decodes as English.
        return whisperPlan(
            summary: whisperSummary,
            languageCode: languageCode,
            isEngineStrict: false
        )
    }

    private func strictApplePlan(podcastLanguageCode: String?) async throws -> EpisodeTranscriptionPlan {
        let languageCode = podcastLanguageCode ?? Self.fallbackLanguageCode
        guard appleSpeechAssets.isTranscriberAvailable else {
            throw AppleSpeechTranscriptionError.transcriberUnavailable
        }
        let (localeIdentifier, status) = await appleSpeechAssets.status(forLanguageCode: languageCode)
        guard let localeIdentifier else {
            throw AppleSpeechTranscriptionError.unsupportedLocale(languageCode)
        }
        guard status == .installed else {
            throw AppleSpeechTranscriptionError.assetsNotInstalled(
                localeIdentifier: localeIdentifier,
                status: status?.rawValue ?? "unknown"
            )
        }
        appleSpeechAssets.recordLocaleUsed(localeIdentifier)
        return applePlan(
            localeIdentifier: localeIdentifier,
            languageCode: languageCode,
            isEngineStrict: true
        )
    }

    private func applePlan(
        localeIdentifier: String,
        languageCode: String,
        isEngineStrict: Bool
    ) -> EpisodeTranscriptionPlan {
        EpisodeTranscriptionPlan(
            runEngine: .appleSpeech,
            modelIdentity: Self.appleModelIdentity(localeIdentifier: localeIdentifier),
            languageCode: languageCode,
            runLanguageCode: languageCode,
            isEngineStrict: isEngineStrict
        )
    }

    private func whisperPlan(
        summary: OpenCastWhisperModelInstalledSummary,
        languageCode: String,
        isEngineStrict: Bool
    ) -> EpisodeTranscriptionPlan {
        EpisodeTranscriptionPlan(
            runEngine: .whisper,
            modelIdentity: EpisodeTranscriptionModelIdentity(summary: summary),
            languageCode: languageCode,
            runLanguageCode: Self.whisperRunLanguageCode,
            isEngineStrict: isEngineStrict
        )
    }

    static func appleModelIdentity(localeIdentifier: String) -> EpisodeTranscriptionModelIdentity {
        EpisodeTranscriptionModelIdentity(
            modelIdentifier: AppleSpeechTranscriptionService.modelIdentifier(
                localeIdentifier: localeIdentifier
            ),
            version: ProcessInfo.processInfo.operatingSystemVersionString,
            treeSHA256: "asset-status-installed-\(localeIdentifier)"
        )
    }
}
