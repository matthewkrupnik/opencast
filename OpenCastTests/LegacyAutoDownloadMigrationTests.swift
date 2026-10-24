import Foundation
import OpenCastCore
import SwiftData
import Testing
@testable import OpenCast

@MainActor
@Suite("Legacy Auto-Download migration")
struct LegacyAutoDownloadMigrationTests {
    private static let podcastID = "https://example.com/legacy-auto.xml"
    private static let goneShowID = "https://example.com/unsubscribed.xml"
    private static let handledPublishedAt = Date(timeIntervalSinceReferenceDate: 790_000_000)

    @Test("A show's old opt-in turns on automatic downloads from its handled episode, and old rows go")
    func migratesOptInWithHandledEpisodeWatermark() async throws {
        let (appModel, context) = try await makeLoadedAppModel(legacyRows: [
            LocalPreferenceRecord(key: "autoDownload.show.\(Self.podcastID)", value: "handled"),
            LocalPreferenceRecord(key: "autoDownload.show.\(Self.goneShowID)", value: "")
        ])

        #expect(appModel.downloadSettings.autoDownloadsNewEpisodes(forPodcastID: Self.podcastID))
        #expect(appModel.downloadSettings.autoDownloadWatermark(forPodcastID: Self.podcastID) == Self.handledPublishedAt)
        #expect(!appModel.downloadSettings.autoDownloadsNewEpisodes(forPodcastID: Self.goneShowID))
        let leftovers = try context.fetch(FetchDescriptor<LocalPreferenceRecord>())
            .filter { $0.key.hasPrefix("autoDownload.show.") }
        #expect(leftovers.isEmpty)
    }

    @Test("A show never checked yet starts from now, so its back catalog is not fetched")
    func uncheckedShowStartsFromNow() async throws {
        let before = Date.now
        let (appModel, _) = try await makeLoadedAppModel(legacyRows: [
            LocalPreferenceRecord(key: "autoDownload.show.\(Self.podcastID)", value: "")
        ])

        let watermark = try #require(appModel.downloadSettings.autoDownloadWatermark(forPodcastID: Self.podcastID))
        #expect(watermark >= before)
    }

    private func makeLoadedAppModel(
        legacyRows: [LocalPreferenceRecord]
    ) async throws -> (OpenCastAppModel, ModelContext) {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let cache = SQLiteLocalLibraryCacheStore.inMemory()
        try await cache.upsertCache(from: feedSnapshot(), refreshedAt: .now)
        context.insert(SubscriptionRecord(feedURL: Self.podcastID, title: "Legacy Show"))
        for row in legacyRows {
            context.insert(row)
        }
        try context.save()
        let appModel = OpenCastAppModel(localLibraryCacheStore: cache, allowsAutomaticFeedRefresh: false)
        await appModel.ensureCoreStoresLoaded(modelContext: context)
        return (appModel, context)
    }

    private func feedSnapshot() throws -> FeedSnapshot {
        let feedURL = try #require(URL(string: Self.podcastID))
        let podcast = Podcast(id: PodcastID(rawValue: Self.podcastID), feedURL: feedURL, title: "Legacy Show")
        return FeedSnapshot(
            podcast: podcast,
            episodes: [
                Episode(
                    id: EpisodeID(rawValue: "handled"),
                    podcastID: podcast.id,
                    podcastTitle: podcast.title,
                    title: "Handled Episode",
                    publishedAt: Self.handledPublishedAt,
                    duration: 60,
                    audioURL: URL(string: "https://example.com/handled.mp3"),
                    guid: "handled"
                )
            ]
        )
    }
}
