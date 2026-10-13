import Foundation
import OpenCastCore
import SwiftData
import Testing
@testable import OpenCast

@MainActor
struct OpenCastSystemActionFixture {
    static let feed = "https://example.com/actions.xml"
    let model: OpenCastAppModel
    let context: ModelContext

    /// `librarySave` stands in for the library's synced-store save, which
    /// every playlist write goes through.
    static func make(episodeCount: Int = 3, queue: UpNextQueueStore? = nil, downloads: DownloadStore? = nil, librarySave: ((ModelContext) throws -> Void)? = nil) async throws -> Self {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        context.insert(SubscriptionRecord(feedURL: feed, title: "A Show"))
        try context.save()
        let cache = SQLiteLocalLibraryCacheStore.inMemory()
        let id = PodcastID(rawValue: feed)
        let episodes = (0..<episodeCount).map { number in
            Episode(id: EpisodeID(rawValue: "episode-\(number)"), podcastID: id, podcastTitle: "A Show", title: "Shared Title", publishedAt: Date(timeIntervalSince1970: Double(number)), duration: 120, audioURL: number == 0 ? nil : URL(string: "https://example.com/\(number).mp3"))
        }
        try await cache.upsertCache(from: FeedSnapshot(podcast: Podcast(id: id, feedURL: URL(string: feed)!, title: "A Show"), episodes: episodes), refreshedAt: .now)
        let library = librarySave.map { LibraryStore(localCache: cache, savePlaybackSkipSettingsModelContext: $0) }
        let model = OpenCastAppModel(library: library, localLibraryCacheStore: cache, downloads: downloads ?? DownloadStore(), upNextQueue: queue ?? UpNextQueueStore(), allowsAutomaticFeedRefresh: false)
        return Self(model: model, context: context)
    }

    /// Inserts four playlists and saves; call it before the first `perform`,
    /// because the rows reach the store only through hydration. "Commute"
    /// lists the show's first two unplayed episodes, `episode-1` and `episode-2`; "All
    /// Played" lists `episode-0`, the one marked played; "Empty" lists a show
    /// the library does not hold; the fourth keeps the default rule.
    func seedPlaylists() async throws -> SeededPlaylists {
        let seeded = SeededPlaylists(
            commuteID: "playlist-commute",
            allPlayedID: "playlist-all-played",
            emptyID: "playlist-empty",
            smartID: "playlist-smart"
        )
        let updatedAt = Date(timeIntervalSince1970: 1_775_000_000)
        let playlists: [(id: String, name: String, rule: PlaylistRule)] = [
            (seeded.commuteID, "Commute", PlaylistRule(podcastIDs: [Self.feed], limit: 2)),
            (seeded.allPlayedID, "All Played", PlaylistRule(podcastIDs: [Self.feed], status: .played)),
            (seeded.emptyID, "Empty", PlaylistRule(podcastIDs: ["https://example.com/elsewhere.xml"])),
            (seeded.smartID, "Unplayed Smart", .default)
        ]
        for (index, playlist) in playlists.enumerated() {
            // Distinct, descending dates give a known "most recently updated" order.
            let date = updatedAt.addingTimeInterval(Double(index) * -60)
            context.insert(
                PlaylistRecord(
                    playlistID: playlist.id,
                    name: playlist.name,
                    kind: .smart,
                    ruleJSON: playlist.rule.normalized().encodedJSON(),
                    createdAt: date,
                    updatedAt: date
                )
            )
        }
        context.insert(EpisodeProgressRecord(episodeID: "episode-0", podcastID: Self.feed, isPlayed: true, updatedAt: updatedAt))
        try context.save()
        return seeded
    }
}

nonisolated struct SeededPlaylists: Sendable {
    let commuteID: String
    let allPlayedID: String
    let emptyID: String
    let smartID: String
}
