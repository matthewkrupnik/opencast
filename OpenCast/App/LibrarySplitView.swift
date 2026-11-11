import SwiftUI

/// The Library tab: a `NavigationSplitView` over the Library's
/// `AppNavigationPaths` slot. The sidebar is the Library; the detail is a
/// stack whose root is the page for `path.first` (the sidebar's selection)
/// with the rest of the path pushed on it. At regular width both columns
/// show; at compact width the split collapses into one stack, showing the
/// detail while the path holds a route, and going back to the sidebar clears
/// the path.
struct LibrarySplitView<Sidebar: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var path: [AppRoute]
    let onOpenEpisode: (String) -> Void
    let onOpenPlaylist: (String) -> Void
    @ViewBuilder let sidebar: () -> Sidebar

    var body: some View {
        let head = path.first
        NavigationSplitView(preferredCompactColumn: compactColumn) {
            sidebar()
                .environment(\.librarySidebar, LibrarySidebar(selectedRoute: head) { route in
                    path = [route]
                })
        } detail: {
            NavigationStack(path: detailPath) {
                Group {
                    if let head {
                        RouteDestinationView(route: head, onOpenEpisode: onOpenEpisode, onOpenPlaylist: onOpenPlaylist)
                            .environment(\.librarySplitDetailClose, LibrarySplitDetailClose(route: head) {
                                path = []
                            })
                    } else {
                        ContentUnavailableView(
                            "No Show Selected",
                            systemImage: "square.stack",
                            description: Text("Choose a show in the Library.")
                        )
                        .accessibilityIdentifier("Library Detail Placeholder")
                    }
                }
                .withOpenCastDestinations(onOpenEpisode: onOpenEpisode, onOpenPlaylist: onOpenPlaylist)
            }
            // A new selection is a new detail stack.
            .id(head)
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// The routes pushed on the detail root.
    private var detailPath: Binding<[AppRoute]> {
        Binding(
            get: { Array(path.dropFirst()) },
            set: { path = Array(path.prefix(1)) + $0 }
        )
    }

    /// The collapsed split shows the detail while the path holds a route;
    /// going back to the sidebar clears it.
    private var compactColumn: Binding<NavigationSplitViewColumn> {
        Binding(
            get: { path.isEmpty ? .sidebar : .detail },
            set: { column in
                if column == .sidebar, horizontalSizeClass == .compact {
                    path = []
                }
            }
        )
    }
}

/// What the Library split's sidebar gives the Library inside it: the route
/// its selection follows (the path's head) and the activation that opens a
/// route as the detail's root. Absent everywhere else, where links keep
/// `NavigationLink`.
struct LibrarySidebar {
    let selectedRoute: AppRoute?
    let activate: (AppRoute) -> Void

    /// For a sidebar `List(selection:)`, whose `NavigationLink(value:)` rows
    /// select their route.
    var selection: Binding<AppRoute?> {
        Binding(
            get: { selectedRoute },
            set: { route in
                if let route {
                    activate(route)
                }
            }
        )
    }
}

/// The detail root's own close, for a page that closes itself with
/// `dismiss` (an unavailable page's Go Back, the feed migration's exit):
/// the detail root is not a pushed page, so `dismiss` cannot remove it.
struct LibrarySplitDetailClose {
    /// The detail root this closes.
    let route: AppRoute
    let close: () -> Void
}

extension EnvironmentValues {
    @Entry var librarySidebar: LibrarySidebar?
    @Entry var librarySplitDetailClose: LibrarySplitDetailClose?
}

/// How a sidebar item outside a `List(selection:)` shows that it is the
/// selection.
enum LibrarySidebarSelectionStyle {
    /// A grid tile: a rounded background behind the tile.
    case tile
    /// An entry inside a shared row (the Library's Notes row).
    case inline
}

/// A Library grid tile that opens `route`: in the split's sidebar a button
/// that makes the route the detail's root and shows the selection; elsewhere
/// a `NavigationLink(value:)`.
struct LibrarySidebarLink<Label: View>: View {
    @Environment(\.librarySidebar) private var sidebar

    let route: AppRoute
    @ViewBuilder let label: Label

    var body: some View {
        if let sidebar {
            Button {
                sidebar.activate(route)
            } label: {
                label
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .librarySidebarSelection(route, style: .tile)
        } else {
            NavigationLink(value: route) {
                label
            }
        }
    }
}

/// The sidebar's highlight on an item whose route is the path's head.
private struct LibrarySidebarSelectionModifier: ViewModifier {
    @Environment(\.librarySidebar) private var sidebar

    let route: AppRoute
    let style: LibrarySidebarSelectionStyle

    func body(content: Content) -> some View {
        let isSelected = sidebar?.selectedRoute == route
        switch style {
        case .tile:
            content
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Self.highlight)
                            .padding(-6)
                    }
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        case .inline:
            content
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Self.highlight)
                            .padding(.horizontal, -8)
                    }
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    /// The selected item's fill: a translucent gray that reads on the
    /// sidebar's white and on its grouped gray alike.
    private static let highlight = Color(uiColor: .systemFill)
}

extension View {
    /// Shows the sidebar's selection on an item that opens `route` through a
    /// callback rather than a `LibrarySidebarLink`.
    func librarySidebarSelection(_ route: AppRoute, style: LibrarySidebarSelectionStyle) -> some View {
        modifier(LibrarySidebarSelectionModifier(route: route, style: style))
    }
}
