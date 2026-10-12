import Foundation
import OpenCastTranscription
import Testing
@testable import OpenCast

@MainActor
@Suite("Episode transcription plan resolver")
struct EpisodeTranscriptionPlanResolverTests {
    @Test("Product default picks Apple when assets are installed")
    func productDefaultPicksAppleWhenInstalled() async throws {
        let harness = Harness()

        let plan = try await harness.resolver.resolve(requestedEngine: .productDefault, podcastLanguageCode: "en-US")

        #expect(plan.runEngine == .appleSpeech)
        #expect(plan.modelIdentity.modelIdentifier == "apple-speech-transcriber.en_US")
        #expect(plan.languageCode == "en-US")
        #expect(plan.runLanguageCode == "en-US")
        #expect(!plan.isEngineStrict)
        #expect(!plan.requiresInstalledWhisperModel)
        #expect(harness.provider.installRequests.isEmpty)
    }

    @Test("Missing podcast language resolves as en-US")
    func missingLanguageResolvesAsEnUS() async throws {
        let harness = Harness()

        let plan = try await harness.resolver.resolve(requestedEngine: .productDefault, podcastLanguageCode: nil)

        #expect(plan.runEngine == .appleSpeech)
        #expect(plan.languageCode == "en-US")
    }

    @Test("Region-less language resolves through locale equivalence")
    func regionlessLanguageResolvesThroughEquivalence() async throws {
        let harness = Harness(
            resolvedLocalesByLanguage: ["fr": "fr_FR"],
            statusesByLocaleIdentifier: ["fr_FR": .installed]
        )

        let plan = try await harness.resolver.resolve(requestedEngine: .productDefault, podcastLanguageCode: "fr")

        #expect(plan.runEngine == .appleSpeech)
        #expect(plan.modelIdentity.modelIdentifier == "apple-speech-transcriber.fr_FR")
        #expect(plan.languageCode == "fr")
    }

    @Test("Product default installs installable assets then picks Apple")
    func productDefaultInstallsThenPicksApple() async throws {
        let harness = Harness(statusesByLocaleIdentifier: ["en_US": .supported])

        let plan = try await harness.resolver.resolve(requestedEngine: .productDefault, podcastLanguageCode: "en-US")

        #expect(plan.runEngine == .appleSpeech)
        #expect(harness.provider.installRequests == ["en_US"])
    }

    @Test("Durable preference pins product default to whisper even when Apple is installed")
    func durablePreferencePinsWhisperTiny() async throws {
        let harness = Harness(whisperInstalled: true, prefersRevocationDurableEngine: true)

        let plan = try await harness.resolver.resolve(requestedEngine: .productDefault, podcastLanguageCode: "en-US")

        #expect(plan.runEngine == .whisper)
        #expect(plan.languageCode == "en-US")
        #expect(plan.runLanguageCode == "en")
        #expect(!plan.isEngineStrict)
        #expect(harness.provider.installRequests.isEmpty)
    }

    @Test("Durable preference without an installed Whisper model routes to consent")
    func durablePreferenceWithoutTinyThrowsMissingSpeechModel() async throws {
        let harness = Harness(whisperInstalled: false, prefersRevocationDurableEngine: true)

        await #expect(throws: EpisodeTranscriptionError.missingSpeechModel) {
            _ = try await harness.resolver.resolve(requestedEngine: .productDefault, podcastLanguageCode: "en-US")
        }
    }

    @Test("Durable preference keeps explicit Apple overrides strict")
    func durablePreferenceKeepsExplicitAppleStrict() async throws {
        let harness = Harness(whisperInstalled: true, prefersRevocationDurableEngine: true)

        let plan = try await harness.resolver.resolve(requestedEngine: .appleSpeech, podcastLanguageCode: "en-US")

        #expect(plan.runEngine == .appleSpeech)
        #expect(plan.isEngineStrict)
    }

    @Test("Product default falls back to whisper when the transcriber is unavailable")
    func productDefaultFallsBackWhenUnavailable() async throws {
        let harness = Harness(isTranscriberAvailable: false, whisperInstalled: true)

        let plan = try await harness.resolver.resolve(requestedEngine: .productDefault, podcastLanguageCode: "en-US")

        #expect(plan.runEngine == .whisper)
        #expect(plan.modelIdentity.modelIdentifier == OpenCastWhisperModel.largeV3.rawValue)
        #expect(plan.runLanguageCode == "en")
        #expect(!plan.isEngineStrict)
        #expect(plan.requiresInstalledWhisperModel)
    }

    @Test("Unsupported locale falls back to whisper with the honest language code")
    func unsupportedLocaleFallsBackWithHonestLanguage() async throws {
        let harness = Harness(whisperInstalled: true)

        let plan = try await harness.resolver.resolve(requestedEngine: .productDefault, podcastLanguageCode: "xx-YY")

        #expect(plan.runEngine == .whisper)
        #expect(plan.languageCode == "xx-YY")
        #expect(plan.runLanguageCode == "en")
    }

    @Test("Asset install failure falls back to whisper")
    func installFailureFallsBackToWhisper() async throws {
        let harness = Harness(
            statusesByLocaleIdentifier: ["en_US": .supported],
            whisperInstalled: true
        )
        harness.provider.installError = FakeAppleSpeechAssetProviderError.installFailed

        let plan = try await harness.resolver.resolve(requestedEngine: .productDefault, podcastLanguageCode: "en-US")

        #expect(plan.runEngine == .whisper)
        #expect(plan.modelIdentity.modelIdentifier == OpenCastWhisperModel.largeV3.rawValue)
    }

    @Test("Fallback without an installed Whisper model throws missingSpeechModel")
    func fallbackWithoutTinyThrowsMissingModel() async {
        let harness = Harness(isTranscriberAvailable: false, whisperInstalled: false)

        await #expect(throws: EpisodeTranscriptionError.missingSpeechModel) {
            _ = try await harness.resolver.resolve(requestedEngine: .productDefault, podcastLanguageCode: nil)
        }
    }

    @Test("Explicit Apple override stays strict and requires installed assets")
    func appleOverrideStrictRequiresInstalledAssets() async throws {
        let installedHarness = Harness()
        let plan = try await installedHarness.resolver.resolve(requestedEngine: .appleSpeech, podcastLanguageCode: nil)
        #expect(plan.runEngine == .appleSpeech)
        #expect(plan.isEngineStrict)

        let supportedOnlyHarness = Harness(statusesByLocaleIdentifier: ["en_US": .supported])
        await #expect(throws: AppleSpeechTranscriptionError.self) {
            _ = try await supportedOnlyHarness.resolver.resolve(requestedEngine: .appleSpeech, podcastLanguageCode: nil)
        }
        #expect(supportedOnlyHarness.provider.installRequests.isEmpty)
    }

    @Test("Explicit whisper override stays strict")
    func whisperOverrideStaysStrict() async throws {
        let harness = Harness(whisperInstalled: true)
        harness.transcriptionModels.loadLocalStatus()

        let plan = try await harness.resolver.resolve(requestedEngine: .selectedWhisperModel, podcastLanguageCode: "de-DE")

        #expect(plan.runEngine == .whisper)
        #expect(plan.isEngineStrict)
        #expect(plan.modelIdentity.modelIdentifier == OpenCastWhisperModel.largeV3.rawValue)
        #expect(plan.languageCode == "en")
    }

    @MainActor
    private struct Harness {
        let provider: FakeAppleSpeechAssetProvider
        let transcriptionModels: TranscriptionModelStore
        let resolver: EpisodeTranscriptionPlanResolver

        init(
            isTranscriberAvailable: Bool = true,
            resolvedLocalesByLanguage: [String: String] = ["en-us": "en_US"],
            statusesByLocaleIdentifier: [String: AppleSpeechAssetLocaleStatus] = ["en_US": .installed],
            whisperInstalled: Bool = false,
            prefersRevocationDurableEngine: Bool = false
        ) {
            provider = FakeAppleSpeechAssetProvider(
                isTranscriberAvailable: isTranscriberAvailable,
                resolvedLocalesByLanguage: resolvedLocalesByLanguage,
                statusesByLocaleIdentifier: statusesByLocaleIdentifier
            )
            transcriptionModels = TranscriptionModelStore(
                installer: FakeResolverModelInstaller(isInstalled: whisperInstalled)
            )
            let suiteName = "plan-resolver-tests-\(UUID().uuidString)"
            let userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
            userDefaults.removePersistentDomain(forName: suiteName)
            resolver = EpisodeTranscriptionPlanResolver(
                transcriptionModels: transcriptionModels,
                appleSpeechAssets: AppleSpeechAssetStore(provider: provider, userDefaults: userDefaults),
                prefersRevocationDurableEngine: prefersRevocationDurableEngine
            )
        }
    }
}

private final class FakeResolverModelInstaller: TranscriptionModelInstalling, @unchecked Sendable {
    var isInstalled: Bool
    private let summary = OpenCastWhisperModelInstalledSummary(
        modelIdentifier: OpenCastWhisperModel.largeV3.rawValue,
        version: OpenCastWhisperModel.largeV3.defaultRemoteVersion,
        totalByteCount: 10,
        treeSHA256: String(repeating: "a", count: 64)
    )

    init(isInstalled: Bool) {
        self.isInstalled = isInstalled
    }

    func installedSummary(model: OpenCastWhisperModel, version: String) throws -> OpenCastWhisperModelInstalledSummary {
        guard isInstalled,
              summary.modelIdentifier == model.rawValue,
              summary.version == version
        else {
            throw OpenCastTranscriptionError.modelNotInstalled(
                modelIdentifier: model.rawValue,
                version: version
            )
        }
        return summary
    }

    func fetchManifest() async throws -> RemoteWhisperModelManifest {
        RemoteWhisperModelManifest(schemaVersion: 1, generatedAt: "2026-07-06T00:00:00Z", models: [])
    }

    func install(
        manifest: RemoteWhisperModelManifest,
        model: OpenCastWhisperModel,
        version: String,
        progress: OpenCastWhisperModelInstallProgressHandler?
    ) async throws -> OpenCastWhisperModelInstalledSummary {
        isInstalled = true
        return summary
    }

    func deleteInstalledModel(model: OpenCastWhisperModel, version: String) throws {
        isInstalled = false
    }
}
