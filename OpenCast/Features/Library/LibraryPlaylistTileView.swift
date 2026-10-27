import SwiftUI

/// A playlist's grid tile: its cover, then its name, sized like the show
/// tiles beside it.
struct LibraryPlaylistTileView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let summary: PlaylistSummary
    let metrics: LibraryGridMetrics

    var body: some View {
        NavigationLink(value: AppRoute.playlistDetail(id: summary.playlistID)) {
            VStack(alignment: .leading, spacing: metrics.isCompact ? 6 : 10) {
                // Matches the show artwork's square and corner radius.
                PlaylistCoverView(tint: summary.tint, size: metrics.tileWidth)

                Text(summary.name)
                    .font(metrics.isCompact ? .subheadline : .headline)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(PlaylistRowView.accessibilityIdentifier(for: summary.playlistID))
    }
}
