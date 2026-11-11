import SwiftData
import SwiftUI

struct LibrarySubscriptionTileView: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @State private var isConfirmingRemoval = false

    let subscription: SubscriptionRecord
    let isCompact: Bool
    let showsNewEpisodeCount: Bool

    private var newEpisodeCount: Int {
        showsNewEpisodeCount ? appModel.library.newEpisodeCount(for: subscription) : 0
    }

    var body: some View {
        let newEpisodeCount = newEpisodeCount

        LibrarySidebarLink(route: .podcastDetail(feedURL: subscription.feedURL)) {
            SubscriptionTileView(subscription: subscription, isCompact: isCompact, badgeCount: newEpisodeCount)
        }
        .buttonStyle(.plain)
        .accessibilityValue(LibraryNewEpisodeBadge.accessibilityValue(count: newEpisodeCount))
        .accessibilityIdentifier(LibrarySubscriptionRowView.accessibilityIdentifier(for: subscription.feedURL))
        .modifier(
            SubscriptionRemovalModifier(
                isConfirmingRemoval: $isConfirmingRemoval,
                subscription: subscription,
                // Compact tiles are too narrow for a trailing swipe action.
                supportsSwipeAction: !isCompact,
                supportsContextMenu: true
            )
        )
    }
}
