import Foundation
import OpenCastCore
import SwiftData
import Testing
@testable import OpenCast

@MainActor
@Suite("Listening history restore")
struct ListeningHistoryRestoreTests {
    private static let podcastID = "https://example.com/history.xml"

    @Test("Restoring a Mark Played puts back the position, unplayed, and brings the swept download back")
    func restoreMarkedPlayedBringsDownloadBack() async throws {
        let fixture = try await makeFixture()
        let episode = try #require(fixture.appModel.episodeSnapshot(for: "first"))
        #expect(fixture.appModel.library.updateProgress(
            episodeID: episode.episodeID,
            podcastID: episode.podcastID,
            position: 1500,
            duration: 3600,
            modelContext: fixture.context
        ))
        #expect(fixture.appModel.downloads.startDownload(for: episode, modelContext: fixture.context))
        #expect(await waitUntil { fixture.appModel.downloads.record(for: episode.episodeID)?.state == .completed })
        #expect(fixture.appModel.downloads.setAutoDeletesPlayedDownloads(true, modelContext: fixture.context))

        fixture.appModel.markEpisodePlayed(episode, modelContext: fixture.context)

        #expect(fixture.appModel.downloads.record(for: episode.episodeID) == nil)
        let entry = try #require(fixture.appModel.listeningHistory.entries.first)
        #expect(entry.kind == .markedPlayed)
        #expect(entry.startPosition == 1500)
        #expect(entry.hadDownload)

        #expect(fixture.appModel.restoreListeningHistoryEntry(entry, modelContext: fixture.context))

        let progress = try #require(fixture.appModel.library.progressRecord(for: episode.episodeID))
        #expect(!progress.isPlayed)
        #expect(progress.position == 1500)
        #expect(await waitUntil { fixture.appModel.downloads.record(for: episode.episodeID)?.state == .completed })
        // Unplayed now, so the played-download sweep leaves it alone.
        fixture.appModel.sweepPlayedDownloadsIfEnabled(modelContext: fixture.context)
        #expect(fixture.appModel.downloads.record(for: episode.episodeID)?.state == .completed)
    }

    @Test("Restoring an entry for a streamed episode downloads nothing")
    func restoreWithoutPriorDownload() async throws {
        let fixture = try await makeFixture()
        let episode = try #require(fixture.appModel.episodeSnapshot(for: "first"))

        fixture.appModel.markEpisodePlayed(episode, modelContext: fixture.context)
        let entry = try #require(fixture.appModel.listeningHistory.entries.first)
        #expect(!entry.hadDownload)

        #expect(fixture.appModel.restoreListeningHistoryEntry(entry, modelContext: fixture.context))

        #expect(fixture.appModel.library.progressRecord(for: episode.episodeID)?.isPlayed == false)
        #expect(fixture.appModel.downloads.record(for: episode.episodeID) == nil)
    }

    private func makeFixture() async throws -> (appModel: OpenCastAppModel, context: ModelContext) {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let cache = SQLiteLocalLibraryCacheStore.inMemory()
        try await cache.upsertCache(from: feedSnapshot(), refreshedAt: .now)
        context.insert(SubscriptionRecord(feedURL: Self.podcastID, title: "History Show"))
        try context.save()
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ListeningHistoryRestoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let appModel = OpenCastAppModel(
            localLibraryCacheStore: cache,
            downloads: DownloadStore(
                downloader: HistoryImmediateAudioDownloader(),
                fileStore: EpisodeDownloadFileStore(baseDirectory: directory)
            ),
            allowsAutomaticFeedRefresh: false
        )
        await appModel.ensureCoreStoresLoaded(modelContext: context)
        return (appModel, context)
    }

    private func feedSnapshot() throws -> FeedSnapshot {
        let feedURL = try #require(URL(string: Self.podcastID))
        let podcast = Podcast(id: PodcastID(rawValue: Self.podcastID), feedURL: feedURL, title: "History Show")
        return FeedSnapshot(
            podcast: podcast,
            episodes: [
                Episode(
                    id: EpisodeID(rawValue: "first"),
                    podcastID: podcast.id,
                    podcastTitle: podcast.title,
                    title: "Episode first",
                    duration: 3600,
                    audioURL: URL(string: "https://example.com/first.mp3"),
                    guid: "first"
                )
            ]
        )
    }
}

private struct HistoryImmediateAudioDownloader: EpisodeAudioDownloading {
    nonisolated func download(
        from sourceURL: URL,
        to temporaryURL: URL,
        resume: EpisodeDownloadResumeContext?,
        onResponseMetadata: @escaping @MainActor @Sendable (EpisodeDownloadResponseMetadata) -> Void,
        progress: @escaping @MainActor @Sendable (_ bytesReceived: Int64, _ bytesExpected: Int64?) -> Void
    ) async throws {
        let data = Data("history audio".utf8)
        await onResponseMetadata(EpisodeDownloadResponseMetadata(entityTag: nil, lastModified: nil))
        try data.write(to: temporaryURL, options: .atomic)
        await progress(Int64(data.count), Int64(data.count))
    }
}
