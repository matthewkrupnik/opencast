import SwiftData
import SwiftUI

/// A show's grid tile: artwork under its refresh status and count badge, then
/// the title. The caller supplies the link around it, so the Library and the
/// Group by Podcast Inbox share the tile but not what it opens or offers.
struct SubscriptionTileView: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let subscription: SubscriptionRecord
    let isCompact: Bool
    /// The count ball over the artwork; zero shows nothing.
    var badgeCount = 0

    private var podcastCache: PodcastCacheSnapshot? {
        appModel.library.podcastCache(for: subscription.feedURL)
    }

    private var isRefreshing: Bool {
        appModel.library.isRefreshing(feedURL: subscription.feedURL)
    }

    private var refreshErrorMessage: String? {
        guard let errorMessage = appModel.library.latestRefreshLogByFeedURL[subscription.feedURL]?.errorMessage,
              !errorMessage.isEmpty
        else {
            return nil
        }

        return errorMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 10) {
            // A square as wide as the grid's column.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        ArtworkPlaceholder(
                            title: subscription.title,
                            imageURL: podcastCache?.artworkURL ?? subscription.artworkURL,
                            size: proxy.size.width,
                            preview: podcastCache.flatMap { appModel.library.artworkPreview(for: $0) },
                            onPreviewResolved: updateArtworkPreview
                        )
                    }
                }
                .overlay(alignment: .topLeading) {
                    refreshStatusOverlay
                }
                .overlay(alignment: .topTrailing) {
                    if badgeCount > 0 {
                        LibraryNewEpisodeBadge(count: badgeCount)
                            .padding(4)
                    }
                }

            Text(subscription.title)
                .font(isCompact ? .subheadline : .headline)
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var refreshStatusOverlay: some View {
        if isRefreshing {
            ProgressView()
                .controlSize(.small)
                .padding(6)
                .glassEffect(.regular, in: .circle)
                .padding(6)
                .accessibilityLabel("Refreshing")
        } else if refreshErrorMessage != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(6)
                .glassEffect(.regular, in: .circle)
                .padding(6)
                .accessibilityLabel("Last refresh failed")
        }
    }

    private func updateArtworkPreview(_ preview: ArtworkPreview) {
        guard let podcastCache else {
            return
        }

        appModel.library.updateArtworkPreview(preview, for: podcastCache)
    }
}
