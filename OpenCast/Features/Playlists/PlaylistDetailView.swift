import SwiftUI

/// One playlist, by ID: its rule's episodes, or an unavailable state once it
/// has been deleted.
struct PlaylistDetailView: View {
    @Environment(OpenCastAppModel.self) private var appModel

    let playlistID: String
    var onOpenEpisode: (String) -> Void = { _ in }

    var body: some View {
        if let summary = appModel.playlists.playlists.first(where: { $0.playlistID == playlistID }) {
            SmartPlaylistDetailView(summary: summary, onOpenEpisode: onOpenEpisode)
        } else {
            ContentUnavailableView("Playlist Unavailable", systemImage: "music.note.list")
                .navigationTitle("Playlist")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
