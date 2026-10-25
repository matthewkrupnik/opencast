import Foundation
import OpenCastCore
import SwiftData
import Testing
@testable import OpenCast

@MainActor
@Suite("CarPlay browse model builder")
struct CarPlayBrowseModelBuilderTests {
    private static let podcastID = "https://example.com/feed.xml"
    private static let podcastTitle = "Test Show"
    private static let floorLimits = CarPlayListLimits(maximumItemCount: 12, maximumSectionCount: 2)
    private static let roomyLimits = CarPlayListLimits(maximumItemCount: 100, maximumSectionCount: 10)

    @Test("Continue leads the playlists only when an episode is loaded and counts against the cap")
    func continueSection() async throws {
        let fixture = try await makeFixture(episodeCount: 20)
        let loaded = try #require(fixture.library.episode(with: episodeID(5)))
        let summaries = (0..<13).map { index in
            makePlaylistSummary(playlistID: "playlist-\(index)", name: "Playlist \(index)")
        }

        let withoutContinue = makePlaylistsSnapshot(summaries, limits: Self.floorLimits)
        let withContinue = makePlaylistsSnapshot(
            summaries,
            currentEpisode: fixture.library.domainEpisode(for: loaded),
            nowPlaying: CarPlayNowPlayingState(episodeID: loaded.episodeID, isPlaying: true),
            limits: Self.floorLimits
        )

        #expect(withoutContinue.sections.map(\.header) == [nil])
        #expect(withContinue.sections.map(\.header) == ["Continue", "Playlists"])
        #expect(withContinue.rowCount == 12)
        #expect(episodeIDs(in: withContinue) == [episodeID(5)])
        #expect(episodeRow(withContinue.sections[0].rows[0])?.isPlaying == true)
        // The Continue row spends one of the twelve slots, so ten playlists
        // plus the marker follow it.
        #expect(withContinue.sections[1].rows.compactMap(playlistRow).map(\.playlistID) == (0..<10).map { "playlist-\($0)" })
        #expect(withContinue.sections[1].rows.last == .showMore)
        #expect(
            withContinue.continuation?.sections.flatMap(\.rows).compactMap(playlistRow).map(\.playlistID)
                == ["playlist-10", "playlist-11", "playlist-12"]
        )
    }

    @Test("Show More appears only past the cap and reaches one further page")
    func showMoreContinuation() async throws {
        let exactFit = try await makeFixture(episodeCount: 12)
        let overflowing = try await makeFixture(episodeCount: 30)

        let fitting = makePlaylistEpisodesSnapshot(library: exactFit.library, limits: Self.floorLimits)
        let truncated = makePlaylistEpisodesSnapshot(library: overflowing.library, limits: Self.floorLimits)

        #expect(fitting.rowCount == 12)
        #expect(fitting.continuation == nil)
        #expect(!fitting.sections.contains { $0.rows.contains(.showMore) })

        let continuation = try #require(truncated.continuation)
        #expect(continuation.title == "More Episodes")
        #expect(continuation.sections.count == 1)
        // The tail resumes exactly where the visible page stopped, is itself
        // capped, and never nests another marker.
        #expect(episodeIDs(in: continuation.snapshot) == (11..<23).map(episodeID))
        #expect(continuation.snapshot.rowCount == 12)
        #expect(continuation.snapshot.continuation == nil)
        #expect(!continuation.sections.contains { $0.rows.contains(.showMore) })
    }

    @Test("A list far past the row-build cap keeps the same page and continuation")
    func farOverCapListKeepsPageAndContinuation() async throws {
        let fixture = try await makeFixture(episodeCount: 60)

        let snapshot = makePlaylistEpisodesSnapshot(library: fixture.library, limits: Self.floorLimits)

        #expect(snapshot.rowCount == 12)
        #expect(episodeIDs(in: snapshot) == (0..<11).map(episodeID))
        let continuation = try #require(snapshot.continuation)
        #expect(episodeIDs(in: continuation.snapshot) == (11..<23).map(episodeID))
        #expect(continuation.snapshot.rowCount == 12)
    }

    @Test("A list that cannot push a further page fills every slot with rows")
    func truncationWithoutMarker() async throws {
        let fixture = try await makeFixture(episodeCount: 30)

        let pushedFromNowPlaying = makePlaylistEpisodesSnapshot(
            library: fixture.library,
            limits: Self.floorLimits.withoutContinuation
        )

        #expect(pushedFromNowPlaying.rowCount == 12)
        #expect(pushedFromNowPlaying.continuation == nil)
        #expect(!pushedFromNowPlaying.sections.contains { $0.rows.contains(.showMore) })
        // The slot the marker would have taken carries a twelfth episode.
        #expect(episodeIDs(in: pushedFromNowPlaying) == (0..<12).map(episodeID))
    }

    @Test("Rows carry playing, progress, and downloaded state")
    func rowStateMapping() async throws {
        let fixture = try await makeFixture(episodeCount: 4)
        let playing = try #require(fixture.library.episode(with: episodeID(0)))
        let inProgress = try #require(fixture.library.episode(with: episodeID(1)))
        let downloaded = try #require(fixture.library.episode(with: episodeID(2)))

        #expect(
            fixture.library.updateProgress(
                episodeID: inProgress.episodeID,
                podcastID: inProgress.podcastID,
                position: 25,
                duration: 100,
                modelContext: fixture.context
            )
        )

        let snapshot = makePlaylistEpisodesSnapshot(
            library: fixture.library,
            downloadRecords: [makeDownloadRecord(episodeID: downloaded.episodeID, state: .completed)],
            nowPlaying: CarPlayNowPlayingState(episodeID: playing.episodeID, isPlaying: true),
            limits: Self.roomyLimits
        )
        let rows = try #require(snapshot.sections.last?.rows)

        #expect(episodeRow(rows[0])?.isPlaying == true)
        // The loaded episode's progress record churns while it plays, so its row
        // deliberately carries no bar.
        #expect(episodeRow(rows[0])?.playbackProgress == nil)
        #expect(episodeRow(rows[1])?.playbackProgress == 0.25)
        #expect(episodeRow(rows[1])?.isPlaying == false)
        #expect(episodeRow(rows[1])?.detailText == Self.podcastTitle)
        #expect(episodeRow(rows[2])?.isDownloaded == true)
        #expect(episodeRow(rows[3])?.isDownloaded == false)
        #expect(episodeRow(rows[3])?.playbackProgress == nil)
    }

    @Test("A loaded but paused episode shows progress instead of the playing indicator")
    func pausedEpisodeIsNotMarkedPlaying() async throws {
        let fixture = try await makeFixture(episodeCount: 3)
        let restored = try #require(fixture.library.episode(with: episodeID(0)))

        #expect(
            fixture.library.updateProgress(
                episodeID: restored.episodeID,
                podcastID: restored.podcastID,
                position: 40,
                duration: 100,
                modelContext: fixture.context
            )
        )

        // The CarPlay cold restore leaves an episode loaded and paused, which is
        // exactly when a playing indicator would be a lie.
        let nowPlaying = CarPlayNowPlayingState(episodeID: restored.episodeID, isPlaying: false)
        let playlists = makePlaylistsSnapshot(
            [makePlaylistSummary(playlistID: "all", name: "All")],
            currentEpisode: fixture.library.domainEpisode(for: restored),
            nowPlaying: nowPlaying,
            limits: Self.roomyLimits
        )
        let episodes = makePlaylistEpisodesSnapshot(
            library: fixture.library,
            nowPlaying: nowPlaying,
            limits: Self.roomyLimits
        )
        let continueRow = try #require(episodeRow(playlists.sections[0].rows[0]))
        let listedRow = try #require(episodeRow(episodes.sections[0].rows[0]))

        #expect(!continueRow.isPlaying)
        #expect(!listedRow.isPlaying)
        #expect(listedRow.playbackProgress == 0.4)
    }

    @Test("Library lists subscriptions with their artwork")
    func librarySubscriptions() async throws {
        let fixture = try await makeFixture(episodeCount: 1)

        let snapshot = CarPlayBrowseModelBuilder.library(
            subscriptions: fixture.library.subscriptions,
            library: fixture.library,
            isLoading: false,
            limits: Self.roomyLimits
        )

        #expect(snapshot.title == "Library")
        #expect(snapshot.sections.count == 1)
        let row = try #require(podcastRow(snapshot.sections[0].rows[0]))
        #expect(row.feedURL == Self.podcastID)
        #expect(row.title == Self.podcastTitle)
        #expect(row.artworkURL == "https://example.com/art.jpg")
    }

    @Test("Per-show list honors the stored filter and sort order")
    func perShowFilterAndSort() async throws {
        let fixture = try await makeFixture(episodeCount: 3)
        let settings = PodcastEpisodeListSettingsStore()
        let played = try #require(fixture.library.episode(with: episodeID(1)))

        #expect(fixture.library.markEpisodePlayed(played, modelContext: fixture.context))

        let defaults = CarPlayBrowseModelBuilder.episodes(
            forPodcastID: Self.podcastID,
            title: Self.podcastTitle,
            library: fixture.library,
            downloadRecords: [],
            episodeListSettings: settings,
            nowPlaying: .idle,
            limits: Self.roomyLimits
        )

        #expect(defaults.title == Self.podcastTitle)
        #expect(episodeIDs(in: defaults) == (0..<3).map(episodeID))

        settings.setFilter(.unplayed, forPodcastID: Self.podcastID, modelContext: fixture.context)
        settings.setSortOrder(.oldestFirst, forPodcastID: Self.podcastID, modelContext: fixture.context)
        let filtered = CarPlayBrowseModelBuilder.episodes(
            forPodcastID: Self.podcastID,
            title: Self.podcastTitle,
            library: fixture.library,
            downloadRecords: [],
            episodeListSettings: settings,
            nowPlaying: .idle,
            limits: Self.roomyLimits
        )

        #expect(episodeIDs(in: filtered) == [episodeID(2), episodeID(0)])
        // Per-show rows trade the podcast title for the publish date, which the
        // show list already implies.
        let oldest = try #require(fixture.library.episode(with: episodeID(2)))
        #expect(
            episodeRow(filtered.sections[0].rows[0])?.detailText
                == oldest.publishedAt?.formatted(.dateTime.month(.abbreviated).day().year())
        )
    }

    @Test("Downloads shows completed downloads newest first, including orphans")
    func downloadsBucket() async throws {
        let fixture = try await makeFixture(episodeCount: 2)
        let libraryEpisode = try #require(fixture.library.episode(with: episodeID(0)))
        let orphan = EpisodeDownloadRecord(
            episodeID: "orphan",
            podcastID: "https://example.com/removed.xml",
            sourceAudioURL: "https://cdn.example.com/orphan.mp3",
            state: .completed,
            episodeTitle: "Orphan Episode",
            podcastTitle: "Removed Podcast",
            updatedAt: Date(timeIntervalSince1970: 500)
        )

        let snapshot = CarPlayBrowseModelBuilder.downloads(
            records: [
                makeDownloadRecord(
                    episodeID: libraryEpisode.episodeID,
                    state: .completed,
                    updatedAt: Date(timeIntervalSince1970: 100)
                ),
                makeDownloadRecord(episodeID: episodeID(1), state: .downloading),
                orphan
            ],
            library: fixture.library,
            nowPlaying: .idle,
            isLoading: false,
            limits: Self.roomyLimits
        )

        #expect(snapshot.title == "Downloads")
        #expect(episodeIDs(in: snapshot) == ["orphan", libraryEpisode.episodeID])
        let orphanRow = try #require(episodeRow(snapshot.sections[0].rows[0]))
        #expect(orphanRow.title == "Orphan Episode")
        #expect(orphanRow.detailText == "Removed Podcast")
        #expect(orphanRow.isDownloaded)
    }

    @Test("Empty lists carry their own empty-state copy, and loading lists spin")
    func emptyAndLoadingStates() async throws {
        let fixture = try await makeFixture(episodeCount: 0)

        let empty = makePlaylistsSnapshot([], limits: Self.roomyLimits)
        let loading = CarPlayBrowseModelBuilder.downloads(
            records: [],
            library: fixture.library,
            nowPlaying: .idle,
            isLoading: true,
            limits: Self.roomyLimits
        )

        #expect(empty.sections.isEmpty)
        #expect(empty.rowCount == 0)
        #expect(empty.continuation == nil)
        #expect(empty.emptyTitleVariants == ["No Playlists", "None"])
        #expect(empty.emptySubtitleVariants == ["Create playlists from OpenCast on your phone."])
        #expect(!empty.showsSpinnerWhileEmpty)
        #expect(loading.emptyTitleVariants == ["Loading…"])
        #expect(loading.emptySubtitleVariants.isEmpty)
        #expect(loading.showsSpinnerWhileEmpty)
    }

    @Test("Snapshots compare equal until a row actually changes")
    func snapshotEquality() async throws {
        let fixture = try await makeFixture(episodeCount: 3)
        let changed = try #require(fixture.library.episode(with: episodeID(2)))

        let first = makePlaylistEpisodesSnapshot(library: fixture.library, limits: Self.roomyLimits)
        let repeated = makePlaylistEpisodesSnapshot(library: fixture.library, limits: Self.roomyLimits)

        #expect(first == repeated)

        let afterDownload = makePlaylistEpisodesSnapshot(
            library: fixture.library,
            downloadRecords: [makeDownloadRecord(episodeID: changed.episodeID, state: .completed)],
            limits: Self.roomyLimits
        )

        #expect(first != afterDownload)
    }

    @Test("The playlists list keeps the store's order and pages at the floor limits")
    func playlistsListRespectsFloorLimitsWithContinuation() throws {
        let summaries = (0..<13).map { index in
            makePlaylistSummary(playlistID: "playlist-\(index)", name: "Playlist \(index)")
        }

        let snapshot = makePlaylistsSnapshot(summaries, limits: .fallback)

        #expect(snapshot.title == "Playlists")
        #expect(snapshot.sections.count == 1)
        #expect(snapshot.sections[0].header == nil)
        #expect(snapshot.rowCount == 12)
        let rows = snapshot.sections[0].rows
        #expect(rows.compactMap(playlistRow).map(\.playlistID) == (0..<11).map { "playlist-\($0)" })
        #expect(rows.last == .showMore)
        let continuation = try #require(snapshot.continuation)
        #expect(continuation.title == "More Playlists")
        #expect(continuation.sections.flatMap(\.rows).compactMap(playlistRow).map(\.playlistID) == ["playlist-11", "playlist-12"])
        #expect(continuation.snapshot.continuation == nil)
    }

    @Test("Playlist rows carry the cover show's artwork, else their symbol, with an inflected count or none")
    func playlistRowsCarryShowArtworkOrSymbol() throws {
        let summaries = [
            makePlaylistSummary(playlistID: "cover", name: "Commute"),
            makePlaylistSummary(playlistID: "bare", name: "Bare"),
            makePlaylistSummary(playlistID: "fresh", name: "Fresh"),
            makePlaylistSummary(playlistID: "starred", name: "Starred")
        ]
        let counts = ["cover": 3, "bare": 0, "fresh": 1, "starred": 12]

        let uncounted = makePlaylistsSnapshot(summaries, episodeCount: { _ in nil }, limits: Self.roomyLimits)
        #expect(uncounted.sections.flatMap(\.rows).compactMap(playlistRow).allSatisfy { $0.detailText == nil })

        // The closure offers a cover to two of them, so the other two prove
        // they fall back to the symbol.
        let bare: Set = ["bare", "starred"]
        let snapshot = makePlaylistsSnapshot(
            summaries,
            episodeCount: { counts[$0.playlistID] ?? -1 },
            artworkURL: { bare.contains($0.playlistID) ? nil : "https://example.com/cover.jpg" },
            limits: Self.roomyLimits
        )

        let rows = snapshot.sections.flatMap(\.rows).compactMap(playlistRow)
        try #require(rows.map(\.playlistID) == summaries.map(\.playlistID))
        #expect(rows.map(\.title) == ["Commute", "Bare", "Fresh", "Starred"])
        #expect(rows[0].artworkURL == "https://example.com/cover.jpg")
        #expect(rows[0].symbolName == nil)
        #expect(rows[0].detailText == "3 episodes")
        #expect(rows[1].artworkURL == nil)
        #expect(rows[1].symbolName == PlaylistRowView.symbolName)
        #expect(rows[1].detailText == "No episodes")
        #expect(rows[2].artworkURL == "https://example.com/cover.jpg")
        #expect(rows[2].symbolName == nil)
        #expect(rows[2].detailText == "1 episode")
        #expect(rows[3].artworkURL == nil)
        #expect(rows[3].symbolName == PlaylistRowView.symbolName)
        #expect(rows[3].detailText == "12 episodes")
    }

    @Test("A playlist's episodes keep input order, carry the playlist and show title, and page like any list")
    func playlistEpisodesKeepOrderTagAndShowTitle() async throws {
        let fixture = try await makeFixture(episodeCount: 13)
        let orderedIDs = [episodeID(4), episodeID(0)] + (0..<13).filter { $0 != 0 && $0 != 4 }.map(episodeID)
        let episodes = try orderedIDs.map { try #require(fixture.library.episode(with: $0)) }

        let snapshot = CarPlayBrowseModelBuilder.playlistEpisodes(
            playlistID: "playlist-commute",
            title: "Commute",
            episodes: episodes,
            library: fixture.library,
            downloadRecords: [],
            nowPlaying: .idle,
            limits: Self.floorLimits
        )
        let empty = CarPlayBrowseModelBuilder.playlistEpisodes(
            playlistID: "playlist-empty",
            title: "Empty",
            episodes: [],
            library: fixture.library,
            downloadRecords: [],
            nowPlaying: .idle,
            limits: Self.floorLimits
        )

        #expect(snapshot.title == "Commute")
        #expect(snapshot.rowCount == 12)
        #expect(episodeIDs(in: snapshot) == Array(orderedIDs.prefix(11)))
        #expect(snapshot.sections.last?.rows.last == .showMore)
        let visibleRows = snapshot.sections.flatMap(\.rows).compactMap(episodeRow)
        #expect(visibleRows.allSatisfy { $0.sourcePlaylistID == "playlist-commute" })
        #expect(visibleRows.allSatisfy { $0.detailText == Self.podcastTitle })
        let continuation = try #require(snapshot.continuation)
        #expect(continuation.title == "More Episodes")
        #expect(episodeIDs(in: continuation.snapshot) == Array(orderedIDs.dropFirst(11)))
        #expect(continuation.sections.flatMap(\.rows).compactMap(episodeRow).allSatisfy { $0.sourcePlaylistID == "playlist-commute" })

        #expect(empty.title == "Empty")
        #expect(empty.sections.isEmpty)
        #expect(empty.rowCount == 0)
        #expect(empty.continuation == nil)
        #expect(empty.emptyTitleVariants.first == "Nothing to Play")
        #expect(empty.emptySubtitleVariants == ["This playlist has no episodes to play."])
    }

    private func makePlaylistsSnapshot(
        _ summaries: [PlaylistSummary],
        episodeCount: (PlaylistSummary) -> Int? = { _ in 2 },
        artworkURL: (PlaylistSummary) -> String? = { _ in nil },
        currentEpisode: Episode? = nil,
        nowPlaying: CarPlayNowPlayingState = .idle,
        limits: CarPlayListLimits
    ) -> CarPlayBrowseSnapshot {
        CarPlayBrowseModelBuilder.playlists(
            summaries,
            episodeCount: episodeCount,
            artworkURL: artworkURL,
            currentEpisode: currentEpisode,
            downloadRecords: [],
            nowPlaying: nowPlaying,
            isLoading: false,
            limits: limits
        )
    }

    /// A playlist over the whole fixture library, in its newest-first order.
    private func makePlaylistEpisodesSnapshot(
        library: LibraryStore,
        downloadRecords: [EpisodeDownloadRecord] = [],
        nowPlaying: CarPlayNowPlayingState = .idle,
        limits: CarPlayListLimits
    ) -> CarPlayBrowseSnapshot {
        CarPlayBrowseModelBuilder.playlistEpisodes(
            playlistID: "playlist-all",
            title: "All",
            episodes: library.episodes,
            library: library,
            downloadRecords: downloadRecords,
            nowPlaying: nowPlaying,
            limits: limits
        )
    }

    private func makeFixture(
        episodeCount: Int
    ) async throws -> (library: LibraryStore, context: ModelContext) {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let cache = SQLiteLocalLibraryCacheStore.inMemory()
        try await cache.upsertCache(
            from: makeFeedSnapshot(episodeCount: episodeCount),
            refreshedAt: .now
        )
        context.insert(
            SubscriptionRecord(
                feedURL: Self.podcastID,
                title: Self.podcastTitle,
                artworkURL: "https://example.com/art.jpg"
            )
        )
        try context.save()
        let library = LibraryStore(localCache: cache)
        await library.load(modelContext: context)
        return (library, context)
    }

    private func makeFeedSnapshot(episodeCount: Int) throws -> FeedSnapshot {
        let feedURL = try #require(URL(string: Self.podcastID))
        let podcast = Podcast(
            id: PodcastID(rawValue: Self.podcastID),
            feedURL: feedURL,
            title: Self.podcastTitle,
            artworkURL: URL(string: "https://example.com/art.jpg")
        )
        return FeedSnapshot(
            podcast: podcast,
            episodes: (0..<episodeCount).map { index in
                Episode(
                    id: EpisodeID(rawValue: episodeID(index)),
                    podcastID: podcast.id,
                    podcastTitle: podcast.title,
                    title: "Episode \(index)",
                    publishedAt: Date(timeIntervalSince1970: Double(episodeCount - index) * 1_000),
                    duration: 100,
                    audioURL: URL(string: "https://example.com/\(episodeID(index)).mp3"),
                    guid: episodeID(index)
                )
            }
        )
    }

    private func makeDownloadRecord(
        episodeID: String,
        state: EpisodeDownloadState,
        updatedAt: Date = Date(timeIntervalSince1970: 0)
    ) -> EpisodeDownloadRecord {
        EpisodeDownloadRecord(
            episodeID: episodeID,
            podcastID: Self.podcastID,
            sourceAudioURL: "https://example.com/\(episodeID).mp3",
            state: state,
            episodeTitle: "Episode \(episodeID)",
            podcastTitle: Self.podcastTitle,
            updatedAt: updatedAt
        )
    }

    private func episodeID(_ index: Int) -> String {
        "episode-\(index)"
    }

    private func episodeIDs(in snapshot: CarPlayBrowseSnapshot) -> [String] {
        snapshot.sections.flatMap(\.rows).compactMap { row in
            switch row {
            case .episode(let episodeRow):
                episodeRow.episodeID
            case .podcast, .playlist, .showMore:
                nil
            }
        }
    }

    private func episodeRow(_ row: CarPlayListRow) -> CarPlayEpisodeRow? {
        guard case .episode(let episodeRow) = row else {
            return nil
        }
        return episodeRow
    }

    private func podcastRow(_ row: CarPlayListRow) -> CarPlayPodcastRow? {
        guard case .podcast(let podcastRow) = row else {
            return nil
        }
        return podcastRow
    }

    private func playlistRow(_ row: CarPlayListRow) -> CarPlayPlaylistRow? {
        guard case .playlist(let playlistRow) = row else {
            return nil
        }
        return playlistRow
    }

    private func makePlaylistSummary(
        playlistID: String,
        name: String
    ) -> PlaylistSummary {
        PlaylistSummary(
            playlistID: playlistID,
            name: name,
            kind: .smart,
            rule: PlaylistRule.default,
            hidesPlayed: false,
            origin: .user,
            itemCount: 0,
            totalDuration: 0,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            coverPodcastIDs: []
        )
    }
}
