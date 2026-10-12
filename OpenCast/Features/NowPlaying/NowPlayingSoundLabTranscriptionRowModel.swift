import Foundation

nonisolated struct NowPlayingSoundLabTranscriptionRowModel: Equatable {
    static let accessibilityIdentifier = "Now Playing Sound Lab Transcript Action"

    let action: NowPlayingSoundLabTranscriptionAction
    let title: String
    let systemImage: String
    let phase: EpisodeAdFreePassPresentationPhase
    let isEnabled: Bool
    let accessibilityValue: String
    let accessibilityIdentifier = Self.accessibilityIdentifier

    init(
        hasCompletedTranscript: Bool,
        localActivity: NowPlayingSoundLabTranscriptionActivity
    ) {
        if hasCompletedTranscript {
            action = .showTranscript
            title = String(localized: "Show Transcript")
            systemImage = "text.quote"
            phase = .completed
            isEnabled = true
            accessibilityValue = String(localized: "Transcript available")
        } else if localActivity == .currentEpisode {
            action = .transcribeLocally
            title = String(localized: "Transcribe")
            systemImage = "waveform"
            phase = .running
            isEnabled = false
            accessibilityValue = String(localized: "Transcription in progress")
        } else if localActivity == .otherEpisode {
            action = .transcribeLocally
            title = String(localized: "Transcribe")
            systemImage = "waveform"
            phase = .running
            isEnabled = false
            accessibilityValue = String(localized: "Another transcription is in progress")
        } else {
            action = .transcribeLocally
            title = String(localized: "Transcribe")
            systemImage = "waveform"
            phase = .idle
            isEnabled = true
            accessibilityValue = ""
        }
    }
}
