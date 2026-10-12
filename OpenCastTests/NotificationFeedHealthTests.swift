import Foundation
import Testing
@testable import OpenCast

@MainActor
@Suite("Notification feed health")
struct NotificationFeedHealthTests {
    @Test("Health records round-trip through the local cache store wholesale")
    func healthRecordsRoundTripThroughLocalCache() async throws {
        let store = SQLiteLocalLibraryCacheStore.inMemory()
        let first = NotificationFeedHealthRecord(
            feedURL: "https://example.com/one.xml",
            health: NotificationFeedHealth(
                consecutiveFailures: 3,
                lastHTTPStatus: 500,
                lastError: "http_error",
                lastPolledAtEpochSeconds: 1_780_000_000
            )
        )
        let second = NotificationFeedHealthRecord(
            feedURL: "https://example.com/two.xml",
            health: NotificationFeedHealth(consecutiveFailures: 0)
        )
        try await store.replaceNotificationFeedHealth([first, second])

        let loaded = try await store.notificationFeedHealthByFeedURL()
        #expect(loaded.count == 2)
        #expect(loaded[first.feedURL] == first.health)
        #expect(loaded[second.feedURL] == second.health)

        // Wholesale replacement drops feeds absent from the newest sync.
        try await store.replaceNotificationFeedHealth([second])
        let replaced = try await store.notificationFeedHealthByFeedURL()
        #expect(replaced.count == 1)
        #expect(replaced[second.feedURL] == second.health)
    }
}
