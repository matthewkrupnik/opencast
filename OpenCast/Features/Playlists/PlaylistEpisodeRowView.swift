import SwiftData
import SwiftUI

/// A playlist episode that still resolves: the Inbox row, played from here
/// by a tap, or by its play button with Tap to Play off (the rest of the
/// playlist plays after it), with the shared episode context menu.
struct PlaylistEpisodeRowView: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @State private var playFeedback = 0

    let playlistID: String
    let episode: EpisodeListItemSnapshot
    let onOpenEpisode: (String) -> Void

    static func accessibilityIdentifier(forEpisodeID episodeID: String) -> String {
        "playlist-episode-\(episodeID)"
    }

    var body: some View {
        Button(action: primaryAction) {
            EpisodeRowView(episode: episode, onPlay: playButtonAction)
        }
        .buttonStyle(.plain)
        .modifier(
            EpisodeRowContextMenuModifier(
                episode: episode,
                showsGoToShow: true,
                onViewDetails: viewEpisodeDetails
            )
        )
        .sensoryFeedback(.impact(flexibility: .soft), trigger: playFeedback)
        .accessibilityIdentifier(Self.accessibilityIdentifier(forEpisodeID: episode.episodeID))
    }

    /// With Tap to Play off the row opens the episode, so the trailing glyph
    /// becomes the play button.
    private var playButtonAction: (() -> Void)? {
        guard !appModel.playbackSettings.isTapToPlayEnabled else {
            return nil
        }
        return play
    }

    private func primaryAction() {
        if appModel.playbackSettings.isTapToPlayEnabled {
            play()
        } else {
            viewEpisodeDetails(episode)
        }
    }

    private func play() {
        nowPlayingProbeMark("playepisode-tap")
        // The app model reports a failed start or an unresolvable episode itself.
        guard appModel.playPlaylistEpisode(episode.episodeID, in: playlistID, modelContext: modelContext) else {
            return
        }
        playFeedback += 1
    }

    private func viewEpisodeDetails(_ episode: EpisodeListItemSnapshot) {
        onOpenEpisode(episode.episodeID)
    }
}
