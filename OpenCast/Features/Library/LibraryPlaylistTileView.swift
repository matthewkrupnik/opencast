import SwiftUI

/// A playlist's grid tile: its tint as a soft gradient square with the
/// playlist symbol, then its name, sized like the show tiles beside it.
struct LibraryPlaylistTileView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let summary: PlaylistSummary
    let metrics: LibraryGridMetrics

    private var tint: PlaylistTint {
        summary.tint ?? .blue
    }

    var body: some View {
        NavigationLink(value: AppRoute.playlistDetail(id: summary.playlistID)) {
            VStack(alignment: .leading, spacing: metrics.isCompact ? 6 : 10) {
                cover

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

    /// Matches the show artwork's square and corner radius.
    private var cover: some View {
        LinearGradient(
            colors: [tint.color.mix(with: .white, by: 0.22), tint.color.mix(with: .black, by: 0.12)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: metrics.tileWidth, height: metrics.tileWidth)
        .overlay {
            Image(systemName: PlaylistRowView.symbolName)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint.prominentLabelColor)
                .padding(metrics.tileWidth * 0.28)
        }
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}
