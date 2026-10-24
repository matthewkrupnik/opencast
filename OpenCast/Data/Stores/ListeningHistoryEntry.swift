import Foundation

/// Value snapshot of a `ListeningHistoryRecord` for views and restore.
struct ListeningHistoryEntry: Identifiable, Equatable {
    enum Kind: String {
        case session
        case markedPlayed
    }

    let id: String
    let kind: Kind
    let episodeID: String
    let podcastID: String
    let startPosition: TimeInterval
    let endPosition: TimeInterval
    let duration: TimeInterval?
    let startedAt: Date
    let endedAt: Date
    let didFinish: Bool
    let hadDownload: Bool
    let isOpen: Bool

    init(_ record: ListeningHistoryRecord) {
        id = record.entryID
        kind = Kind(rawValue: record.kind) ?? .session
        episodeID = record.episodeID
        podcastID = record.podcastID
        startPosition = record.startPosition
        endPosition = record.endPosition
        duration = record.duration
        startedAt = record.startedAt
        endedAt = record.endedAt
        didFinish = record.didFinish
        hadDownload = record.hadDownload
        isOpen = record.isOpen
    }
}

/// What history watches on the player: which episode is loaded and whether
/// it is audibly playing.
nonisolated struct ListeningHistoryPlaybackActivity: Equatable, Sendable {
    let episodeID: String?
    let isPlaying: Bool
}
