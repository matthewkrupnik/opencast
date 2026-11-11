import SwiftUI

/// A playlist's grid tile: its cover, then its name and episode count, sized
/// like the show tiles beside it. A playlist with nothing left to play is
/// greyed.
struct LibraryPlaylistTileView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let summary: PlaylistSummary
    let isCompact: Bool
    /// Nil until the playlist's episodes are loaded.
    let episodeCount: Int?
    let hasUnplayedEpisodes: Bool

    var body: some View {
        LibrarySidebarLink(route: .playlistDetail(id: summary.playlistID)) {
            VStack(alignment: .leading, spacing: isCompact ? 6 : 10) {
                // Matches the show artwork's square and corner radius.
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        GeometryReader { proxy in
                            PlaylistCoverView(tint: summary.tint, size: proxy.size.width)
                        }
                    }
                    .grayscale(hasUnplayedEpisodes ? 0 : 1)
                    .opacity(hasUnplayedEpisodes ? 1 : 0.5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.name)
                        .font(isCompact ? .subheadline : .headline)
                        .foregroundStyle(hasUnplayedEpisodes ? .primary : .secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let episodeCount {
                        Text(PlaylistSummaryText.line(itemCount: episodeCount, totalDuration: 0))
                            .font(isCompact ? .caption : .subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(PlaylistRowView.accessibilityIdentifier(for: summary.playlistID))
    }
}
