import Foundation
import SwiftData

/// One stretch of listening, or one Mark Played, kept on this device so it can
/// be put back. `startPosition` is the restore point: where playback stood
/// before the entry changed anything.
@Model
final class ListeningHistoryRecord {
    var entryID: String = UUID().uuidString
    /// A `ListeningHistoryEntry.Kind` raw value.
    var kind: String = ""
    var episodeID: String = ""
    var podcastID: String = ""
    var startPosition: Double = 0
    var endPosition: Double = 0
    var duration: Double?
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    var didFinish: Bool = false
    /// Whether a completed download existed when the entry began, so a
    /// restore knows to bring a swept download back.
    var hadDownload: Bool = false
    /// Still being extended by playback; launch closes any left open.
    var isOpen: Bool = false

    init(
        entryID: String = UUID().uuidString,
        kind: ListeningHistoryEntry.Kind,
        episodeID: String,
        podcastID: String,
        startPosition: Double,
        endPosition: Double,
        duration: Double?,
        startedAt: Date,
        endedAt: Date,
        didFinish: Bool = false,
        hadDownload: Bool,
        isOpen: Bool
    ) {
        self.entryID = entryID
        self.kind = kind.rawValue
        self.episodeID = episodeID
        self.podcastID = podcastID
        self.startPosition = startPosition
        self.endPosition = endPosition
        self.duration = duration
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.didFinish = didFinish
        self.hadDownload = hadDownload
        self.isOpen = isOpen
    }
}
