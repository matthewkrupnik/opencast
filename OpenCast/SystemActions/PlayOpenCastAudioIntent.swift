import AppIntents

@AppIntent(schema: .audio.playAudio)
struct PlayOpenCastAudioIntent: AudioPlaybackIntent {
    static let isAssistantOnly = true
    static var supportedModes: IntentModes { .foreground }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    var audioEntity: OpenCastAudioItem.Value
    var playbackAttributes: Set<OpenCastAudioPlaybackAttribute>
    var warmupAudioQueueResult: OpenCastAudioQueueResult?
    var queueLocation: OpenCastAudioQueueLocation?

    func perform() async throws -> some IntentResult {
        guard playbackAttributes.isEmpty, warmupAudioQueueResult == nil else {
            throw OpenCastSystemActionError.unsupportedPlaybackOptions
        }
        // There is no queue to add to: playback follows the playlist an
        // episode was started from.
        guard queueLocation == nil else { throw OpenCastSystemActionError.unsupportedPlaybackOptions }
        let action: OpenCastSystemAction = switch audioEntity {
        case .episode(let episode): .playEpisode(episode.id)
        case .show(let show): .playLatest(show.id)
        }
        try await OpenCastIntentAccess.perform(action)
        return .result()
    }
}
