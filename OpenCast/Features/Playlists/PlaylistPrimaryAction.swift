import Foundation

/// The playlist hero's Play label: Resume when the episode Play would start
/// is already in progress, otherwise Play.
enum PlaylistPrimaryAction: Equatable {
    case play
    case resume

    var title: String {
        switch self {
        case .play:
            "Play"
        case .resume:
            "Resume"
        }
    }

    /// The label over a playlist's evaluation, or nil when Play has nothing
    /// to start. Playlists use the Episodes chip's definition of unplayed,
    /// which also counts a position at the end as played, so the first
    /// episode not completed is the one `playPlaylist` starts.
    static func resolve(smartEpisodes episodes: [EpisodeListItemSnapshot], library: LibraryStore) -> PlaylistPrimaryAction? {
        for episode in episodes {
            let progress = library.progressSummary(for: episode)
            if !progress.isCompleted {
                return progress.hasVisibleProgress ? .resume : .play
            }
        }
        return nil
    }
}
