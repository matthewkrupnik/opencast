import AppIntents

struct PauseOpenCastPlaybackIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Pause Playback"
    nonisolated static let description = IntentDescription("Pause the episode playing in OpenCast.")
    // Pausing never needs the app on screen.
    nonisolated static var supportedModes: IntentModes { .background }
    nonisolated static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult {
        try await OpenCastIntentAccess.perform(.pause)
        return .result()
    }
}
