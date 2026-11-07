import SwiftUI
import Testing
@testable import OpenCast

/// The show page's per-visit settings across two-pane container switches
/// (its episode search). A switch rebuilds the page from
/// its route; the ledger above the containers keeps what the visit changed.
/// "Switch" below is what `TwoPaneRoot` does: the same section path, the
/// other container's scope, a page rebuilt from the same route.
@MainActor
@Suite("Two-pane root visit ledger")
struct TwoPaneRootVisitLedgerTests {
    private static let feed = "https://example.com/feed.xml"
    private static let show = AppRoute.podcastDetail(feedURL: feed)
    private static let episode = AppRoute.episodeDetail(id: "episode-1")

    /// The section as `TwoPaneRoot` runs it: the path, the scene's
    /// container, and the current host's writer (a new host, so a new token,
    /// at every switch), whose visit scope the rebuilt page reads.
    @MainActor
    private final class Root {
        let state = TwoPaneRootVisitState()
        var container = TwoPaneRootContainer.split
        var path: [AppRoute] = []
        private var token = TwoPaneRootWriterToken()

        private var pathBinding: Binding<[AppRoute]> {
            Binding(get: { self.path }, set: { self.path = $0 })
        }

        /// The current host's scope, as a rebuilt page reads it.
        var current: TwoPaneRootVisitScope {
            let kind: TwoPaneRootWriter.Kind = container == .split ? .detail(head: path.first) : .stack
            let containerBinding = Binding(get: { self.container }, set: { self.container = $0 })
            return TwoPaneRootWriter.make(kind, token: token, path: pathBinding, container: containerBinding, section: "test")
                .visitScope(state)
        }

        func setPath(_ newPath: [AppRoute]) {
            path = newPath
            state.retainVisits(in: newPath)
        }

        /// A fold or rotation: the other container, the same path, a new host.
        func switchContainer() {
            container = container == .split ? .stack : .split
            token = TwoPaneRootWriterToken()
            state.retainVisits(in: path)
        }

        func update(_ route: AppRoute, in scope: TwoPaneRootVisitScope, _ change: (inout PodcastDetailVisit) -> Void) {
            var visit = scope.podcastDetailVisit(for: route) ?? PodcastDetailVisit(route: route)
            change(&visit)
            scope.setPodcastDetailVisit(visit, for: route)
        }

        func visit(_ route: AppRoute) -> PodcastDetailVisit? {
            current.podcastDetailVisit(for: route)
        }
    }

    private static let typed = PodcastDetailVisit.Search(query: "deterministic", mode: .episodes)

    @Test("A new visit starts with no search")
    func newVisitStartsEmpty() {
        let ledger = TwoPaneRootVisitLedger()
        #expect(ledger.podcastDetailVisit(for: Self.show).search == nil)
    }

    @Test("Clearing the path ends the visit")
    func clearingThePath() {
        let root = Root()
        root.setPath([Self.show])
        root.update(Self.show, in: root.current) { $0.search = Self.typed }
        root.setPath([])
        root.switchContainer()
        root.setPath([Self.show])
        #expect(root.visit(Self.show)?.search == nil)
    }

    @Test("Returning from a nested page keeps the visit, across a switch too")
    func returningFromANestedPage() {
        let root = Root()
        root.setPath([Self.show])
        root.update(Self.show, in: root.current) { $0.search = Self.typed }
        root.setPath([Self.show, Self.episode])
        root.switchContainer()
        root.setPath([Self.show])
        #expect(root.visit(Self.show)?.search == Self.typed)
    }

    /// The show page's search decides what it lists: a visit setting.
    @Test("A typed search survives a switch either way with the same query, mode and request", arguments: [
        TwoPaneRootContainer.split, .stack
    ])
    func searchSurvivesSwitches(startingIn container: TwoPaneRootContainer) {
        let root = Root()
        root.container = container
        root.setPath([Self.show])
        let page = root.current
        root.update(Self.show, in: page) { $0.search = PodcastDetailVisit.Search() }
        root.update(Self.show, in: page) {
            $0.search?.query = "deterministic"
            $0.search?.mode = .fullText
        }
        let before = root.visit(Self.show)

        root.switchContainer()
        // The outgoing page's search ends as it is torn down: its write is
        // dropped, so the rebuilt page finds the visit's search.
        root.update(Self.show, in: page) { $0.search = nil }
        let after = root.visit(Self.show)
        #expect(after == before)
        #expect(after?.search?.query == "deterministic")
        #expect(after?.search?.mode == .fullText)
        // The same query, mode and episodes are the same request, hence the
        // same results.
        let episodes: [EpisodeListItemSnapshot] = []
        #expect(
            EpisodeSearchRequestKey(episodes: episodes, query: before?.search?.query ?? "", mode: before?.search?.mode ?? .episodes)
                == EpisodeSearchRequestKey(episodes: episodes, query: after?.search?.query ?? "", mode: after?.search?.mode ?? .episodes)
        )

        // Back the other way, and the user's own Cancel still ends it.
        root.switchContainer()
        #expect(root.visit(Self.show)?.search?.query == "deterministic")
        root.update(Self.show, in: root.current) { $0.search = nil }
        #expect(root.visit(Self.show)?.search == nil)
    }

    /// The Notes page's search query is carried as the show
    /// page's search is.
    @Test("The Notes page's query survives a switch either way; the outgoing page's write is dropped; the visit ends with the path", arguments: [
        TwoPaneRootContainer.split, .stack
    ])
    func notesQuerySurvivesSwitches(startingIn container: TwoPaneRootContainer) {
        let root = Root()
        root.container = container
        root.setPath([.notes])
        let page = root.current
        page.setNotesSearchQuery("chapter", for: .notes)
        #expect(root.current.notesSearchQuery(for: .notes) == "chapter")

        root.switchContainer()
        // The outgoing page's field empties as it is torn down: dropped.
        page.setNotesSearchQuery("", for: .notes)
        #expect(root.current.notesSearchQuery(for: .notes) == "chapter")
        root.switchContainer()
        #expect(root.current.notesSearchQuery(for: .notes) == "chapter")

        // Returning from a nested page keeps it; leaving Notes ends it.
        root.setPath([.notes, Self.episode])
        root.setPath([.notes])
        #expect(root.current.notesSearchQuery(for: .notes) == "chapter")
        root.setPath([])
        root.setPath([.notes])
        #expect(root.current.notesSearchQuery(for: .notes) == "")
    }

    @Test("An outgoing host's visit writes are dropped; the current one's land", arguments: [
        TwoPaneRootContainer.split, .stack
    ])
    func scopeWrites(startingIn container: TwoPaneRootContainer) {
        let root = Root()
        root.container = container
        root.setPath([Self.show])
        let outgoing = root.current
        root.switchContainer()
        root.update(Self.show, in: outgoing) { $0.search = Self.typed }
        #expect(root.visit(Self.show)?.search == nil)
        root.update(Self.show, in: root.current) { $0.search = Self.typed }
        #expect(root.visit(Self.show)?.search == Self.typed)
    }

    @Test("Without a two-pane root a page keeps its visit to itself")
    func ledgerRetainsOnlyThePath() {
        var ledger = TwoPaneRootVisitLedger()
        var visit = ledger.podcastDetailVisit(for: Self.show)
        visit.search = Self.typed
        ledger.setPodcastDetailVisit(visit, for: Self.show)
        ledger.retainVisits(in: [Self.episode])
        #expect(ledger == TwoPaneRootVisitLedger())
    }
}
