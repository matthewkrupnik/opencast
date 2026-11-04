import Foundation
import Testing
@testable import OpenCast

@MainActor
@Suite("Playlist count snapshots")
struct PlaylistCountSnapshotStoreTests {
    private typealias Snapshot = PlaylistCountSnapshotStore.Snapshot

    @Test("A snapshot persists across instances and applies only to its rule")
    func persistsPerRule() throws {
        try withDefaults { defaults in
            let snapshot = Snapshot(ruleJSON: "rule-a", count: 7, hasUnplayedEpisodes: false)
            PlaylistCountSnapshotStore(defaults: defaults)
                .record(snapshot, for: "p1", listedPlaylistIDs: ["p1"])

            let reopened = PlaylistCountSnapshotStore(defaults: defaults)
            #expect(reopened.snapshot(for: "p1", ruleJSON: "rule-a") == snapshot)
            #expect(reopened.snapshot(for: "p1", ruleJSON: "rule-b") == nil)
            #expect(reopened.snapshot(for: "p2", ruleJSON: "rule-a") == nil)
        }
    }

    @Test("Recording drops playlists no longer listed")
    func prunesUnlistedPlaylists() throws {
        try withDefaults { defaults in
            let store = PlaylistCountSnapshotStore(defaults: defaults)
            store.record(Snapshot(ruleJSON: "r", count: 1, hasUnplayedEpisodes: true), for: "gone", listedPlaylistIDs: ["gone"])
            store.record(Snapshot(ruleJSON: "r", count: 2, hasUnplayedEpisodes: true), for: "kept", listedPlaylistIDs: ["kept"])

            let reopened = PlaylistCountSnapshotStore(defaults: defaults)
            #expect(reopened.snapshot(for: "gone", ruleJSON: "r") == nil)
            #expect(reopened.snapshot(for: "kept", ruleJSON: "r")?.count == 2)
        }
    }

    @Test("Remove All clears the saved snapshots")
    func removeAllClears() throws {
        try withDefaults { defaults in
            let store = PlaylistCountSnapshotStore(defaults: defaults)
            store.record(Snapshot(ruleJSON: "r", count: 3, hasUnplayedEpisodes: true), for: "p", listedPlaylistIDs: ["p"])
            store.removeAll()

            #expect(store.snapshot(for: "p", ruleJSON: "r") == nil)
            #expect(defaults.object(forKey: PlaylistCountSnapshotStore.defaultsKey) == nil)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "PlaylistCountSnapshotStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        try body(defaults)
    }
}
