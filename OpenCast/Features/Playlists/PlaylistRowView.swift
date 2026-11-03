import SwiftUI

/// A playlist in the collection: the playlist symbol in its color, its name,
/// and its episode count. A playlist with nothing left to play is greyed.
struct PlaylistRowView: View {
    static let symbolName = "music.note.list"

    let summary: PlaylistSummary
    /// Nil until the playlist's episodes are loaded.
    let episodeCount: Int?
    let hasUnplayedEpisodes: Bool

    static func accessibilityIdentifier(for playlistID: String) -> String {
        "playlist-row-\(playlistID)"
    }

    var body: some View {
        NavigationLink(value: AppRoute.playlistDetail(id: summary.playlistID)) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.name)
                        .foregroundStyle(hasUnplayedEpisodes ? .primary : .secondary)
                    if let episodeCount {
                        Text(PlaylistSummaryText.line(itemCount: episodeCount, totalDuration: 0))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: Self.symbolName)
                    .foregroundStyle(hasUnplayedEpisodes ? summary.tint.color : .secondary)
            }
        }
        .accessibilityIdentifier(Self.accessibilityIdentifier(for: summary.playlistID))
    }
}
