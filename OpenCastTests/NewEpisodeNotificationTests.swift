import Foundation
import OpenCastCore
import Testing
import UserNotifications
@testable import OpenCast

@MainActor
@Suite("Local new-episode notifications")
struct NewEpisodeNotificationTests {
    nonisolated private static let now = Date(timeIntervalSince1970: 1_790_000_000)
    nonisolated private static let feedURL = "https://example.com/feed.xml"

    // MARK: Detector

    @Test("The first fetch of a feed is a silent baseline")
    func firstFetchIsBaseline() {
        let snapshot = Self.snapshot([Self.episode("new", hoursAgo: 1)])
        #expect(NewEpisodeDetector.detect(preexisting: [], snapshot: snapshot, now: Self.now).isEmpty)
    }

    @Test("Genuinely new episodes are detected")
    func newEpisodesDetected() {
        let snapshot = Self.snapshot([Self.episode("old", hoursAgo: 48), Self.episode("new", hoursAgo: 1)])
        let found = NewEpisodeDetector.detect(preexisting: [Self.cached("old", hoursAgo: 48)], snapshot: snapshot, now: Self.now)
        #expect(found.map(\.episodeID) == ["new"])
        #expect(found.first?.feedURL == Self.feedURL)
        #expect(found.first?.podcastTitle == "Example Show")
    }

    @Test("Back catalogue, stale, future-dated, and salvaged items never qualify")
    func ineligibleItemsSkipped() {
        let preexisting = [Self.cached("known", hoursAgo: 10)]
        let snapshot = Self.snapshot([
            Self.episode("rekeyed-old", hoursAgo: 30),
            Self.episode("too-old", hoursAgo: 80),
            Self.episode("future", hoursAgo: -2)
        ])
        #expect(NewEpisodeDetector.detect(preexisting: preexisting, snapshot: snapshot, now: Self.now).isEmpty)

        var salvaged = Self.snapshot([Self.episode("new", hoursAgo: 1)])
        salvaged.isSalvaged = true
        #expect(NewEpisodeDetector.detect(preexisting: preexisting, snapshot: salvaged, now: Self.now).isEmpty)
    }

    // MARK: Ledger

    @Test("The ledger announces each episode once, across reloads")
    func ledgerDeduplicates() async {
        let url = FileManager.default.temporaryDirectory.appending(path: "ledger-\(UUID().uuidString).json")
        let ledger = NewEpisodeNotificationLedger(fileURL: url, now: { Self.now })
        #expect(await ledger.admit([Self.candidate("a"), Self.candidate("b")]).map(\.episodeID) == ["a", "b"])
        #expect(await ledger.admit([Self.candidate("a")]).isEmpty)

        let reloaded = NewEpisodeNotificationLedger(fileURL: url, now: { Self.now })
        #expect(await reloaded.admit([Self.candidate("b"), Self.candidate("c")]).map(\.episodeID) == ["c"])
    }

    @Test("Ledger entries expire after the retention window")
    func ledgerPrunes() async {
        let url = FileManager.default.temporaryDirectory.appending(path: "ledger-\(UUID().uuidString).json")
        _ = await NewEpisodeNotificationLedger(fileURL: url, now: { Self.now }).admit([Self.candidate("a")])
        let later = NewEpisodeNotificationLedger(
            fileURL: url,
            now: { Self.now.addingTimeInterval(NewEpisodeNotificationLedger.retention + 1) }
        )
        #expect(await later.admit([Self.candidate("a")]).count == 1)
    }

    // MARK: Scheduler

    @Test("The payload matches what tap routing and the content extension read")
    func payloadShape() throws {
        var candidate = Self.candidate("episode-1")
        candidate.summary = "<p>Show &amp; tell</p>"
        candidate.duration = 2_940
        let content = NewEpisodeNotificationScheduler.content(for: candidate)

        #expect(content.categoryIdentifier == OpenCastNotificationCategory.episode)
        #expect(content.title == "Example Show")
        #expect(content.subtitle == "Episode episode-1")
        #expect(content.body == "Show & tell")
        #expect(content.targetContentIdentifier == "episode-1")
        #expect(content.threadIdentifier == NewEpisodeNotificationScheduler.threadIdentifier(feedURL: Self.feedURL))
        let payload = try #require(content.userInfo["opencast"] as? [String: Any])
        #expect(payload["kind"] as? String == "episode")
        #expect(payload["feed_url"] as? String == Self.feedURL)
        #expect(payload["episode_id"] as? String == "episode-1")
        #expect(payload["episode_duration_text"] as? String == "49 MIN")
    }

    @Test("Nothing posts while the app is active or permission is missing")
    func suppressedWhenActiveOrUnauthorized() async {
        let center = RecordingNotificationCenter(status: .authorized)
        let scheduler = NewEpisodeNotificationScheduler(center: center, artwork: { _ in nil })
        await scheduler.post([Self.candidate("a")], isSceneActive: true)
        #expect(center.requests.isEmpty)

        center.status = .denied
        await scheduler.post([Self.candidate("a")], isSceneActive: false)
        #expect(center.requests.isEmpty)
    }

    @Test("Up to three episodes post individually; more collapse into one summary")
    func groupingCollapsesLargeBatches() async {
        let center = RecordingNotificationCenter(status: .authorized)
        let scheduler = NewEpisodeNotificationScheduler(center: center, artwork: { _ in nil })

        await scheduler.post((1...3).map { Self.candidate("e\($0)") }, isSceneActive: false)
        #expect(center.requests.map(\.identifier) == ["opencast-episode-e1", "opencast-episode-e2", "opencast-episode-e3"])

        await scheduler.post((1...5).map { Self.candidate("f\($0)") }, isSceneActive: false)
        #expect(center.requests.count == 4)
        #expect(center.requests.last?.content.title == "5 new episodes")
    }

    // MARK: Fixtures

    static func candidate(_ id: String) -> NewEpisodeCandidate {
        NewEpisodeCandidate(
            episodeID: id,
            feedURL: feedURL,
            podcastTitle: "Example Show",
            title: "Episode \(id)",
            summary: nil,
            publishedAt: now,
            duration: nil,
            episodeArtworkURL: nil,
            podcastArtworkURL: nil
        )
    }

    private static func episode(_ id: String, hoursAgo: Double) -> Episode {
        Episode(
            id: EpisodeID(rawValue: id),
            podcastID: PodcastID(rawValue: feedURL),
            podcastTitle: "Example Show",
            title: "Episode \(id)",
            publishedAt: now.addingTimeInterval(-hoursAgo * 3_600)
        )
    }

    private static func cached(_ id: String, hoursAgo: Double) -> EpisodeListItemSnapshot {
        EpisodeListItemSnapshot(
            episodeID: id,
            podcastID: feedURL,
            podcastTitle: "Example Show",
            title: "Episode \(id)",
            summary: nil,
            publishedAt: now.addingTimeInterval(-hoursAgo * 3_600),
            duration: nil,
            audioURL: nil,
            artworkURL: nil,
            artworkPreview: nil,
            guid: id,
            cachedAt: now
        )
    }

    private static func snapshot(_ episodes: [Episode]) -> FeedSnapshot {
        FeedSnapshot(
            podcast: Podcast(id: PodcastID(rawValue: feedURL), feedURL: URL(string: feedURL)!, title: "Example Show"),
            episodes: episodes,
            fetchedAt: now
        )
    }
}

private final class RecordingNotificationCenter: AdFreePassNotificationCenter, @unchecked Sendable {
    var status: UNAuthorizationStatus
    private(set) var requests: [UNNotificationRequest] = []

    init(status: UNAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestProvisionalAuthorization() async {}

    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
    }
}
