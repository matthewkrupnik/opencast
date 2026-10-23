import Foundation
import OpenCastCore
import SwiftData
import Testing
@testable import OpenCast

/// A single-feed refresh splices that feed's episodes into the published
/// list; these pin the splice to exactly what a full SQLite load publishes.
@MainActor
@Suite(.serialized)
struct LibraryFeedScopedReloadTests {
    private let feedA = URL(string: "https://example.com/a.xml")!
    private let feedB = URL(string: "https://example.com/b.xml")!
    private let feedC = URL(string: "https://example.com/c.xml")!
    private let day: TimeInterval = 24 * 60 * 60
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func singleFeedRefreshPublishesWhatAFullLoadWould() async throws {
        let cache = LoadRecordingCacheStore(wrapping: SQLiteLocalLibraryCacheStore.inMemory())
        try await seedLibrary(in: cache)
        let context = try subscribedContext(to: [feedA, feedB, feedC])
        // B gains an episode tied with A's newest, loses one, retitles an
        // undated one so it sorts among C's undated episodes.
        let refreshedB = snapshot(feedB, episodes: [
            ("b-new", base, "B New"),
            ("b-1", base - day, "B One"),
            ("b-undated", nil, "Middle"),
        ])
        let service = FixedFeedService(snapshots: [feedB: refreshedB])
        let library = LibraryStore(feedService: service, localCache: cache, now: { self.base })
        #expect(await library.load(modelContext: context))
        await cache.resetRecordedLoads()

        await library.refresh(feedURL: feedB.absoluteString, modelContext: context)

        #expect(await cache.recordedLoads().allSatisfy(\.isEmpty), "a single-feed refresh must not rematerialize every feed")
        #expect(library.episode(with: "b-new") != nil)
        let spliced = publishedState(library)

        try await library.reloadFromStore(modelContext: context)

        #expect(await cache.recordedLoads().contains { !$0.isEmpty })
        #expect(spliced == publishedState(library))
    }

    @Test func feedReloadBeforeAnyPublicationRunsTheFullLoad() async throws {
        let cache = LoadRecordingCacheStore(wrapping: SQLiteLocalLibraryCacheStore.inMemory())
        try await seedLibrary(in: cache)
        let context = try subscribedContext(to: [feedA, feedB, feedC])
        let library = LibraryStore(feedService: FixedFeedService(snapshots: [:]), localCache: cache, now: { self.base })

        try await library.reloadFeedsFromStore([feedB.absoluteString], modelContext: context)

        #expect(await cache.recordedLoads().contains { !$0.isEmpty })
        #expect(Set(library.episodes.map(\.podcastID)) == Set([feedA, feedB, feedC].map(\.absoluteString)))
    }

    @Test func feedReloadAfterASubscriptionChangeRunsTheFullLoad() async throws {
        let cache = LoadRecordingCacheStore(wrapping: SQLiteLocalLibraryCacheStore.inMemory())
        try await seedLibrary(in: cache)
        let context = try subscribedContext(to: [feedA, feedB, feedC])
        let library = LibraryStore(feedService: FixedFeedService(snapshots: [:]), localCache: cache, now: { self.base })
        #expect(await library.load(modelContext: context))
        for record in try context.fetch(FetchDescriptor<SubscriptionRecord>())
        where record.feedURL == feedC.absoluteString {
            context.delete(record)
        }
        try context.save()
        await cache.resetRecordedLoads()

        try await library.reloadFeedsFromStore([feedB.absoluteString], modelContext: context)

        #expect(await cache.recordedLoads().contains { !$0.isEmpty })
        #expect(Set(library.episodes.map(\.podcastID)) == Set([feedA, feedB].map(\.absoluteString)))
    }

    // MARK: - Fixtures

    private struct PublishedState: Equatable {
        let episodes: [EpisodeListItemSnapshot]
        let episodesByPodcastID: [String: [EpisodeListItemSnapshot]]
        let podcastIDs: [String: String]
    }

    private func publishedState(_ library: LibraryStore) -> PublishedState {
        let podcastIDs = [feedA, feedB, feedC].map(\.absoluteString)
        return PublishedState(
            episodes: library.episodes,
            episodesByPodcastID: Dictionary(uniqueKeysWithValues: podcastIDs.map { ($0, library.episodes(forPodcastID: $0)) }),
            podcastIDs: Dictionary(uniqueKeysWithValues: library.episodes.map {
                ($0.episodeID, library.episode(with: $0.episodeID)?.podcastID ?? "")
            })
        )
    }

    private func seedLibrary(in cache: LoadRecordingCacheStore) async throws {
        try await cache.upsertCache(from: snapshot(feedA, episodes: [
            ("a-1", base, "A One"),
            ("a-2", base - 2 * day, "A Two"),
            ("a-undated", nil, "Alpha"),
        ]), refreshedAt: base - day)
        try await cache.upsertCache(from: snapshot(feedB, episodes: [
            ("b-1", base - day, "B One"),
            ("b-2", base - 3 * day, "B Two"),
            ("b-undated", nil, "Zulu"),
        ]), refreshedAt: base - day)
        try await cache.upsertCache(from: snapshot(feedC, episodes: [
            ("c-1", base - day, "C One"),
            ("c-undated-1", nil, "Lima"),
            ("c-undated-2", nil, "Middle"),
        ]), refreshedAt: base - day)
    }

    private func snapshot(_ feedURL: URL, episodes: [(id: String, publishedAt: Date?, title: String)]) -> FeedSnapshot {
        let podcastID = PodcastID(rawValue: feedURL.absoluteString)
        return FeedSnapshot(
            podcast: Podcast(id: podcastID, feedURL: feedURL, title: feedURL.lastPathComponent),
            episodes: episodes.map { episode in
                Episode(
                    id: EpisodeID(rawValue: episode.id), podcastID: podcastID,
                    podcastTitle: feedURL.lastPathComponent, title: episode.title,
                    publishedAt: episode.publishedAt,
                    audioURL: URL(string: "https://example.com/\(episode.id).mp3"),
                    guid: "guid-\(episode.id)"
                )
            }
        )
    }

    private func subscribedContext(to feedURLs: [URL]) throws -> ModelContext {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        for feedURL in feedURLs {
            context.insert(SubscriptionRecord(feedURL: feedURL.absoluteString, title: feedURL.lastPathComponent))
        }
        try context.save()
        return context
    }
}

private actor FixedFeedService: FeedService {
    private let snapshots: [String: FeedSnapshot]

    init(snapshots: [URL: FeedSnapshot]) {
        self.snapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.key.absoluteString, $0.value) })
    }

    func prepareFeed(at url: URL, validators _: FeedValidators?) async throws -> PreparedFeedOutcome {
        guard let snapshot = snapshots[url.absoluteString] else {
            throw OpenCastCoreError.unexpectedStatusCode(599)
        }
        return PreparedFeedOutcome(feed: try PreparedFeed(snapshot: snapshot))
    }

    func fetchFeed(at url: URL) async throws -> FeedSnapshot {
        guard let feed = try await prepareFeed(at: url, validators: nil).feed else {
            throw OpenCastCoreError.invalidHTTPResponse
        }
        return try feed.materialized()
    }
}

/// Records each `loadLibrary` call's active set: an empty set loads podcast
/// rows and refresh logs only, a non-empty one materializes every episode.
private actor LoadRecordingCacheStore: LocalLibraryCacheStore {
    private let wrapped: SQLiteLocalLibraryCacheStore
    private var loads: [Set<String>] = []

    init(wrapping wrapped: SQLiteLocalLibraryCacheStore) {
        self.wrapped = wrapped
    }

    func recordedLoads() -> [Set<String>] { loads }
    func resetRecordedLoads() { loads.removeAll() }

    func loadLibrary(activePodcastIDs: Set<String>) async throws -> LocalLibraryCacheSnapshot {
        loads.append(activePodcastIDs)
        return try await wrapped.loadLibrary(activePodcastIDs: activePodcastIDs)
    }

    func allRefreshLogs() async throws -> [RefreshLogSnapshot] { try await wrapped.allRefreshLogs() }
    func episodeDetail(episodeID: String) async throws -> EpisodeDetailSnapshot? {
        try await wrapped.episodeDetail(episodeID: episodeID)
    }
    func showNotesHTMLByEpisodeID(activePodcastIDs: Set<String>) async throws -> [String: String] {
        try await wrapped.showNotesHTMLByEpisodeID(activePodcastIDs: activePodcastIDs)
    }
    func upsertCache(from prepared: PreparedFeed, refreshedAt: Date) async throws {
        try await wrapped.upsertCache(from: prepared, refreshedAt: refreshedAt)
    }
    func upsertCache(from snapshot: FeedSnapshot, refreshedAt: Date) async throws {
        try await wrapped.upsertCache(from: snapshot, refreshedAt: refreshedAt)
    }
    func updateEpisodeArtworkPreview(_ preview: ArtworkPreview, episodeID: String, artworkURL: String?) async throws {
        try await wrapped.updateEpisodeArtworkPreview(preview, episodeID: episodeID, artworkURL: artworkURL)
    }
    func updatePodcastArtworkPreview(_ preview: ArtworkPreview, feedURL: String, artworkURL: String?) async throws {
        try await wrapped.updatePodcastArtworkPreview(preview, feedURL: feedURL, artworkURL: artworkURL)
    }
    func insertRefreshLog(_ log: RefreshLogSnapshot, prunedTo retentionLimit: Int) async throws {
        try await wrapped.insertRefreshLog(log, prunedTo: retentionLimit)
    }
    func feedValidators(forPodcastID podcastID: String) async throws -> FeedValidators? {
        try await wrapped.feedValidators(forPodcastID: podcastID)
    }
    func updateFeedValidators(_ validators: FeedValidators, forPodcastID podcastID: String) async throws {
        try await wrapped.updateFeedValidators(validators, forPodcastID: podcastID)
    }
    func recordFeedRetryFailure(forPodcastID podcastID: String, attemptedAt: Date) async throws {
        try await wrapped.recordFeedRetryFailure(forPodcastID: podcastID, attemptedAt: attemptedAt)
    }
    func clearFeedRetryFailure(forPodcastID podcastID: String) async throws {
        try await wrapped.clearFeedRetryFailure(forPodcastID: podcastID)
    }
    func cachedEpisodes(forPodcastID podcastID: String) async throws -> [EpisodeListItemSnapshot] {
        try await wrapped.cachedEpisodes(forPodcastID: podcastID)
    }
    func deleteEpisodes(episodeIDs: [String]) async throws { try await wrapped.deleteEpisodes(episodeIDs: episodeIDs) }
    func deleteCache(forPodcastID podcastID: String) async throws { try await wrapped.deleteCache(forPodcastID: podcastID) }
    func deleteAllLocalCache() async throws { try await wrapped.deleteAllLocalCache() }
    func replaceNotificationFeedHealth(_ records: [NotificationFeedHealthRecord]) async throws {
        try await wrapped.replaceNotificationFeedHealth(records)
    }
    func notificationFeedHealthByFeedURL() async throws -> [String: NotificationFeedHealth] {
        try await wrapped.notificationFeedHealthByFeedURL()
    }
    func hasCompletedLegacyImport() async throws -> Bool { try await wrapped.hasCompletedLegacyImport() }
    func importLegacyCache(
        podcasts: [PodcastCacheSnapshot],
        episodes: [EpisodeDetailSnapshot],
        refreshLogs: [RefreshLogSnapshot]
    ) async throws {
        try await wrapped.importLegacyCache(podcasts: podcasts, episodes: episodes, refreshLogs: refreshLogs)
    }
}
