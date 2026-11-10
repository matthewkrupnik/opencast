import Foundation
import OpenCastCore

nonisolated struct PlaybackChapterList: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case embedded
        /// The feed's `podcast:chapters` JSON document.
        case feed
        case generated(transcriptSourceSHA256: String)
    }

    static let restartThreshold: TimeInterval = 3

    /// The listed chapters, sorted by start time.
    let chapters: [EpisodeChapter]
    /// Every chapter, hidden ones included, for the art timeline.
    private let artTimeline: [EpisodeChapter]
    let source: Source

    static let empty = PlaybackChapterList(chapters: [], source: .embedded)

    init(chapters: [EpisodeChapter], source: Source) {
        artTimeline = chapters.sorted { $0.startTime < $1.startTime }
        self.chapters = artTimeline.filter { !$0.isHidden }
        self.source = source
    }

    var isEmpty: Bool {
        chapters.isEmpty
    }

    func chapter(at position: TimeInterval) -> EpisodeChapter? {
        chapters.last { $0.startTime <= position }
    }

    func ordinal(of chapter: EpisodeChapter) -> Int? {
        chapters.firstIndex(of: chapter).map { $0 + 1 }
    }

    func nextChapter(after position: TimeInterval) -> EpisodeChapter? {
        chapters.first { $0.startTime > position }
    }

    func previousChapter(before position: TimeInterval) -> EpisodeChapter? {
        guard let current = chapter(at: position) else {
            return nil
        }
        if position - current.startTime > Self.restartThreshold {
            return current
        }
        // Chapters that share a start would bounce between themselves:
        // step back to the last strictly earlier start.
        return chapters.last { $0.startTime < current.startTime }
    }

    /// Whether any listed chapter carries art, so lists can make room for it.
    var hasChapterArt: Bool {
        chapters.contains { $0.imageURL != nil }
    }

    /// Whether any chapter, hidden ones included, carries art.
    var hasAnyArt: Bool {
        artTimeline.contains { $0.imageURL != nil }
    }

    /// The art for `position`: the latest chapter that has started and not
    /// passed its own end, hidden ones included. Nil means the episode artwork.
    func imageURL(at position: TimeInterval) -> URL? {
        artTimeline.last { chapter in
            chapter.startTime <= position && (chapter.endTime.map { position < $0 } ?? true)
        }?.imageURL
    }

    var timelineMarkers: [TimeInterval] {
        chapters.map(\.startTime).filter { $0 > 0 }
    }
}
