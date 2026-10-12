import SwiftUI

struct NowPlayingSoundLabPanelHost: View {
    @Environment(OpenCastAppModel.self) private var appModel

    let revealProgress: CGFloat
    @Binding var voiceBoostEnabled: Bool
    let voiceBoostControlEnabled: Bool
    let onAdFreePassAction: () -> Void
    let onTranscriptAction: () -> Void
    let onAdFreePassBackgroundProbe: () -> Void

    var body: some View {
        NowPlayingSoundLabPanel(
            revealProgress: revealProgress,
            voiceBoostEnabled: $voiceBoostEnabled,
            voiceBoostControlEnabled: voiceBoostControlEnabled,
            adFreePassRow: NowPlayingSoundLabAdFreePassRowModel(
                presentation: appModel.currentAdFreePassPresentation
            ),
            transcriptionRow: transcriptionRow,
            onAdFreePassAction: onAdFreePassAction,
            onTranscriptAction: onTranscriptAction,
            onAdFreePassBackgroundProbe: onAdFreePassBackgroundProbe
        )
    }

    private var transcriptionRow: NowPlayingSoundLabTranscriptionRowModel? {
        guard let episodeID = appModel.playback.currentEpisode?.id.rawValue else {
            return nil
        }

        let localRequest = appModel.transcriptionRequests.request
        let localRequestEpisodeID: String? = if let localRequest, !localRequest.phase.isTerminal {
            localRequest.episodeID
        } else {
            nil
        }
        return NowPlayingSoundLabTranscriptionRowModel(
            hasCompletedTranscript: appModel.transcriptions.hasCompletedTranscript(for: episodeID),
            localActivity: NowPlayingSoundLabTranscriptionStateResolver.activity(
                currentEpisodeID: episodeID,
                requestEpisodeID: localRequestEpisodeID,
                storeEpisodeID: appModel.transcriptions.activeEpisodeID
            )
        )
    }
}
