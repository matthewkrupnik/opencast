import SwiftUI

struct NowPlayingMoreMenu: View {
    /// The cached snapshot of the current episode, for sharing; nil when the
    /// episode is neither cached nor downloaded.
    let episode: EpisodeListItemSnapshot?
    let hasTranscript: Bool
    let canShowDescription: Bool
    let canShowShow: Bool
    /// The name of the playlist playback came from; nil when there is none.
    let playlistSourceName: String?
    /// Whether Add Note and Private Notes appear; follows the Playback
    /// setting for private notes, so a listener who hasn't opted in sees
    /// neither.
    let showsPrivateNotes: Bool
    let onTranscriptAction: () -> Void
    let onAddNote: () -> Void
    let onShowNotes: () -> Void
    let onShowDescription: () -> Void
    let onShowShow: () -> Void
    let onShowPlaylist: () -> Void
    let onShowHistory: () -> Void
    let onStopPlayback: () -> Void

    var body: some View {
        Menu {
            if let episode {
                Section {
                    EpisodeShareMenu(episode: episode)
                }
            }
            Button(
                hasTranscript ? "Show Transcript" : "Generate Transcript",
                systemImage: "text.quote",
                action: onTranscriptAction
            )
            if showsPrivateNotes {
                Button("Add Note", systemImage: "square.and.pencil", action: onAddNote)
                    .accessibilityIdentifier("Add Timestamped Note")
                Button("Private Notes", systemImage: "note.text", action: onShowNotes)
                    .accessibilityIdentifier("Menu Private Notes")
            }
            Button("Show Description", systemImage: "info.circle", action: onShowDescription)
                .disabled(!canShowDescription)
            Button("Go to Show", systemImage: "rectangle.stack", action: onShowShow)
                .disabled(!canShowShow)
            if let playlistSourceName {
                Button(
                    PlaylistPlaybackSourceText.showPlaylistMenuTitle(name: playlistSourceName),
                    systemImage: "music.note.list",
                    action: onShowPlaylist
                )
            }
            Button("Listening History", systemImage: "clock.arrow.circlepath", action: onShowHistory)
            Divider()
            Button("Stop Playback", systemImage: "stop.circle", action: onStopPlayback)
        } label: {
            Label("More Actions", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .nowPlayingToolbarHitTarget()
                // On the label: glass around the Menu itself morphs the menu
                // out of the circle on iOS 27, and the first item tap is lost.
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
    }
}
