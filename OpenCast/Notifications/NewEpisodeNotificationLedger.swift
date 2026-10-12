import Foundation

/// Device-local record of episodes already announced, so foreground and
/// background refreshes never announce the same episode twice.
actor NewEpisodeNotificationLedger {
    static let retention: TimeInterval = 14 * 24 * 60 * 60

    private let fileURL: URL
    private let now: @Sendable () -> Date
    private var notifiedAt: [String: Date]?

    init(
        fileURL: URL = URL.applicationSupportDirectory
            .appending(path: "NewEpisodeNotifications", directoryHint: .isDirectory)
            .appending(path: "ledger.json"),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.fileURL = fileURL
        self.now = now
    }

    /// Records and returns the candidates not announced before.
    func admit(_ candidates: [NewEpisodeCandidate]) -> [NewEpisodeCandidate] {
        var notified = loaded()
        let cutoff = now().addingTimeInterval(-Self.retention)
        notified = notified.filter { $0.value >= cutoff }
        var admitted: [NewEpisodeCandidate] = []
        for candidate in candidates where notified[candidate.episodeID] == nil {
            notified[candidate.episodeID] = now()
            admitted.append(candidate)
        }
        notifiedAt = notified
        save(notified)
        return admitted
    }

    func reset() {
        notifiedAt = [:]
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func loaded() -> [String: Date] {
        if let notifiedAt {
            return notifiedAt
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let stored = (try? Data(contentsOf: fileURL)).flatMap { try? decoder.decode([String: Date].self, from: $0) }
        return stored ?? [:]
    }

    private func save(_ notified: [String: Date]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(notified) else {
            return
        }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
