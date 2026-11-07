import SwiftUI

/// What a split's detail column shows when its section's path is empty.
enum TwoPaneRootPlaceholder {
    case library

    var title: String {
        switch self {
        case .library:
            "No Show Selected"
        }
    }

    var systemImage: String {
        switch self {
        case .library:
            "square.stack"
        }
    }

    var description: String {
        switch self {
        case .library:
            "Choose a show in the Library."
        }
    }
}

/// The root of a split's detail stack: the page for the path's head, through
/// the same destination switch the stacks use, or the placeholder. Only this
/// root gets the close action; the pages pushed above it keep `dismiss`.
struct TwoPaneRootDetailRoot: View {
    let route: AppRoute?
    let placeholder: TwoPaneRootPlaceholder
    let onOpenEpisode: (String) -> Void
    let onOpenPlaylist: (String) -> Void
    let close: TwoPaneRootCloseAction?

    var body: some View {
        if let route {
            RouteDestinationView(route: route, onOpenEpisode: onOpenEpisode, onOpenPlaylist: onOpenPlaylist)
                .environment(\.twoPaneRootClose, close)
        } else {
            ContentUnavailableView(
                placeholder.title,
                systemImage: placeholder.systemImage,
                description: Text(placeholder.description)
            )
            .accessibilityIdentifier("Two-Pane Root Placeholder")
        }
    }
}
