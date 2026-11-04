import Foundation

/// Each playlist's last evaluated count and playability, kept on this device
/// so a launch can show them before the library loads. A snapshot applies
/// only to the rule it was taken under. Device-local on purpose: a synced
/// field would write to iCloud whenever a count changed.
final class PlaylistCountSnapshotStore {
    struct Snapshot: Codable, Equatable {
        var ruleJSON: String
        var count: Int
        var hasUnplayedEpisodes: Bool
    }

    static let defaultsKey = "playlistCountSnapshots"

    private let defaults: UserDefaults
    private var snapshots: [String: Snapshot]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        snapshots = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([String: Snapshot].self, from: $0) } ?? [:]
    }

    func snapshot(for playlistID: String, ruleJSON: String) -> Snapshot? {
        guard let snapshot = snapshots[playlistID], snapshot.ruleJSON == ruleJSON else {
            return nil
        }
        return snapshot
    }

    /// Saves only on a change, and drops playlists no longer listed.
    func record(_ snapshot: Snapshot, for playlistID: String, listedPlaylistIDs: Set<String>) {
        var updated = snapshots.filter { listedPlaylistIDs.contains($0.key) }
        updated[playlistID] = snapshot
        guard updated != snapshots else {
            return
        }
        snapshots = updated
        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    func removeAll() {
        snapshots = [:]
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
