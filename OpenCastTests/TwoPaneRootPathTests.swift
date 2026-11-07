import Testing
@testable import OpenCast

/// The two-pane roots' path contract: one canonical
/// path per section, the split's columns derived from it, and the writes
/// each container may make.
@MainActor
@Suite("Two-pane root path contract")
struct TwoPaneRootPathTests {
    private static let feed = "https://example.com/feed.xml"
    private static let otherFeed = "https://example.com/other.xml"

    private static let show = AppRoute.podcastDetail(feedURL: feed)
    private static let otherShow = AppRoute.podcastDetail(feedURL: otherFeed)
    private static let episode = AppRoute.episodeDetail(id: "episode-1")
    private static let transcript = AppRoute.episodeTranscript(id: "episode-1")

    @Test("The split derives its detail root and stack from the path: empty, one and deep")
    func headAndSuffix() {
        #expect(TwoPaneRootPath.head(of: []) == nil)
        #expect(TwoPaneRootPath.suffix(of: []).isEmpty)
        #expect(TwoPaneRootPath.head(of: [Self.show]) == Self.show)
        #expect(TwoPaneRootPath.suffix(of: [Self.show]).isEmpty)
        let deep = [Self.show, Self.episode, Self.transcript]
        #expect(TwoPaneRootPath.head(of: deep) == Self.show)
        #expect(TwoPaneRootPath.suffix(of: deep) == [Self.episode, Self.transcript])
    }

    @Test("A root activation replaces the path in the split and pushes in the stack")
    func rootActivation() {
        // Split: from empty, from one, from deep, and reselecting the head.
        #expect(TwoPaneRootPath.openingFromRoot(Self.show, in: [], container: .split) == [Self.show])
        #expect(TwoPaneRootPath.openingFromRoot(Self.otherShow, in: [Self.show], container: .split) == [Self.otherShow])
        #expect(
            TwoPaneRootPath.openingFromRoot(.notes, in: [Self.show, Self.episode, Self.transcript], container: .split)
                == [.notes]
        )
        #expect(TwoPaneRootPath.openingFromRoot(Self.show, in: [Self.show, Self.episode], container: .split) == [Self.show])
        // Stack: today's push.
        #expect(TwoPaneRootPath.openingFromRoot(Self.show, in: [], container: .stack) == [Self.show])
        #expect(
            TwoPaneRootPath.openingFromRoot(Self.episode, in: [Self.show], container: .stack) == [Self.show, Self.episode]
        )
    }

    @Test("Every route a root opens can be the detail's root", arguments: [
        AppRoute.podcastDetail(feedURL: "https://example.com/feed.xml"),
        .episodeDetail(id: "episode-1"),
        .playlistDetail(id: "playlist-1"),
        .notes
    ])
    func everyRootRoute(route: AppRoute) {
        let path = TwoPaneRootPath.openingFromRoot(route, in: [Self.otherShow, Self.episode], container: .split)
        #expect(TwoPaneRootPath.head(of: path) == route)
        #expect(TwoPaneRootPath.suffix(of: path).isEmpty)
    }

    @Test("Detail pushes and pops keep the head")
    func detailPushAndPop() {
        let pushed = TwoPaneRootPath.writingDetailSuffix(
            [Self.episode],
            forHead: Self.show,
            into: [Self.show],
            currentContainer: .split
        )
        #expect(pushed == [Self.show, Self.episode])
        let deeper = TwoPaneRootPath.writingDetailSuffix(
            [Self.episode, Self.transcript],
            forHead: Self.show,
            into: [Self.show, Self.episode],
            currentContainer: .split
        )
        #expect(deeper == [Self.show, Self.episode, Self.transcript])
        let popped = TwoPaneRootPath.writingDetailSuffix(
            [],
            forHead: Self.show,
            into: [Self.show, Self.episode, Self.transcript],
            currentContainer: .split
        )
        #expect(popped == [Self.show])
    }

    @Test("An obsolete detail stack never overwrites a newer path")
    func obsoleteDetailWrites() {
        // The head was replaced (a sidebar activation, a deep link): the old
        // detail stack's teardown write is dropped.
        #expect(
            TwoPaneRootPath.writingDetailSuffix([], forHead: Self.show, into: [Self.otherShow], currentContainer: .split)
                == nil
        )
        // The path was cleared: the placeholder's stack is the current one.
        #expect(
            TwoPaneRootPath.writingDetailSuffix([Self.episode], forHead: Self.show, into: [], currentContainer: .split)
                == nil
        )
        // The split is the outgoing container.
        #expect(
            TwoPaneRootPath.writingDetailSuffix([], forHead: Self.show, into: [Self.show, Self.episode], currentContainer: .stack)
                == nil
        )
    }

    @Test("Under the placeholder a detail write becomes the path")
    func placeholderWrites() {
        #expect(
            TwoPaneRootPath.writingDetailSuffix([Self.show], forHead: nil, into: [], currentContainer: .split)
                == [Self.show]
        )
        // Once a head exists, the placeholder's stack is obsolete.
        #expect(
            TwoPaneRootPath.writingDetailSuffix([], forHead: nil, into: [Self.show], currentContainer: .split) == nil
        )
    }

    @Test("The stack writes only while it is the current container")
    func stackWrites() {
        #expect(TwoPaneRootPath.writingStackPath([Self.show, Self.episode], currentContainer: .stack) == [Self.show, Self.episode])
        #expect(TwoPaneRootPath.writingStackPath([], currentContainer: .stack) == [])
        // The outgoing stack's teardown write is dropped.
        #expect(TwoPaneRootPath.writingStackPath([], currentContainer: .split) == nil)
    }

    /// External writes (a notification's route, Now Playing's Go to, a
    /// reset) are authoritative: the split derives its columns from them.
    @Test("External replacement and deep links change or remove the head")
    func externalReplacement() {
        var paths = AppNavigationPaths()
        paths[.library] = [Self.show, Self.episode]
        // `openRouteInLibrary`: the head changes without a sidebar tap.
        paths[.library] = [Self.episode]
        #expect(TwoPaneRootPath.head(of: paths[.library]) == Self.episode)
        #expect(TwoPaneRootPath.suffix(of: paths[.library]).isEmpty)
        // `openRouteFromNowPlaying` on an empty path: the appended route is
        // the head.
        paths[.downloads] = []
        paths[.downloads].append(Self.show)
        #expect(TwoPaneRootPath.head(of: paths[.downloads]) == Self.show)
        // On a path with a head it is pushed in the detail.
        paths[.downloads].append(Self.episode)
        #expect(TwoPaneRootPath.head(of: paths[.downloads]) == Self.show)
        #expect(TwoPaneRootPath.suffix(of: paths[.downloads]) == [Self.episode])
        // A reset removes the head: the placeholder.
        paths.removeAll()
        #expect(TwoPaneRootPath.head(of: paths[.library]) == nil)
        #expect(TwoPaneRootPath.head(of: paths[.downloads]) == nil)
    }

    @Test("Pruning can remove the head, the suffix or both")
    func pruning() {
        var paths = AppNavigationPaths()
        paths[.library] = [Self.show, Self.episode, Self.transcript]
        // The episode left the library: the suffix shrinks, the head stays.
        paths.removeAll { $0 == Self.episode }
        #expect(paths[.library] == [Self.show, Self.transcript])
        // The show was unsubscribed: the next route becomes the head.
        paths.removeAll { route in
            if case .podcastDetail(let feedURL) = route { return feedURL == Self.feed }
            return false
        }
        #expect(TwoPaneRootPath.head(of: paths[.library]) == Self.transcript)
        paths.removeAll { _ in true }
        #expect(TwoPaneRootPath.head(of: paths[.library]) == nil)
    }

    @Test("The split's own close clears the path only while its route is the head")
    func closingTheRoot() {
        #expect(TwoPaneRootPath.closingRoot(Self.show, in: [Self.show]) == [])
        #expect(TwoPaneRootPath.closingRoot(Self.show, in: [Self.show, Self.episode]) == [])
        #expect(TwoPaneRootPath.closingRoot(Self.show, in: [Self.otherShow]) == nil)
        #expect(TwoPaneRootPath.closingRoot(Self.show, in: []) == nil)
    }

    @Test("The sidebar's highlight is the head, by the complete route")
    func sidebarSelection() {
        let sidebar = TwoPaneRootSidebar(selectedRoute: TwoPaneRootPath.head(of: [Self.show, Self.episode])) { _ in }
        #expect(sidebar.isSelected(Self.show))
        #expect(!sidebar.isSelected(Self.otherShow))
        #expect(!sidebar.isSelected(Self.episode))
        let empty = TwoPaneRootSidebar(selectedRoute: TwoPaneRootPath.head(of: [])) { _ in }
        #expect(!empty.isSelected(Self.show))
    }

    /// A switch rebuilds the container from the same path: the route
    /// sequence and the visible page are the path's, in both directions.
    @Test("A container switch keeps the route sequence and the visible page")
    func switchKeepsThePath() {
        let path = [Self.show, Self.episode, Self.transcript]
        // Split → stack: the stack shows the path's last route over the root.
        #expect(TwoPaneRootPath.writingStackPath(path, currentContainer: .stack) == path)
        // Stack → split: the head is the detail root, the rest its stack;
        // the visible page is still the last route.
        let head = TwoPaneRootPath.head(of: path)
        let suffix = TwoPaneRootPath.suffix(of: path)
        #expect(head.map { [$0] + suffix } == path)
        #expect(suffix.last == path.last)
        // An empty path: the root content alone (stack) or beside the
        // placeholder (split).
        #expect(TwoPaneRootPath.head(of: []) == nil)
    }
}
