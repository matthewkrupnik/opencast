import Foundation
import OpenCastPlayback

/// What the scrub bubble says about the point the thumb is being dragged to,
/// resolved apart from the view so the chapter and zone lookups are testable.
nonisolated struct NowPlayingScrubPreview: Equatable, Sendable {
    /// Matches the rail: auto-skip zones are drawn solid, display-only zones
    /// dimmed, so the note distinguishes the two the same way. Neither says
    /// "skipped": a scrub that lands in an auto-skip zone disarms it
    /// (`PlaybackAdSkipPolicy`), so the listener hears what they aimed at.
    enum Zone: Equatable, Sendable {
        case adBreak
        case possibleAd

        var note: String {
            switch self {
            case .adBreak:
                "Ad break"
            case .possibleAd:
                "Possible ad"
            }
        }
    }

    let time: TimeInterval
    /// Nil while the duration is unknown, like the elapsed/remaining row.
    let remaining: TimeInterval?
    let chapterTitle: String?
    let zone: Zone?

    init(
        time: TimeInterval,
        duration: TimeInterval?,
        chapters: PlaybackChapterList,
        zones: [PlaybackSkipZone],
        displayOnlyZones: [PlaybackSkipZone]
    ) {
        self.time = time
        if let duration, duration.isFinite, duration > 0 {
            remaining = max(duration - time, 0)
        } else {
            remaining = nil
        }

        let title = chapters.chapter(at: time)?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        chapterTitle = title?.isEmpty == false ? title : nil

        // The tiers shouldn't overlap, but if they do the confident one wins.
        if zones.contains(where: { Self.contains(time, in: $0) }) {
            zone = .adBreak
        } else if displayOnlyZones.contains(where: { Self.contains(time, in: $0) }) {
            zone = .possibleAd
        } else {
            zone = nil
        }
    }

    /// Half-open like `PlaybackAdSkipPolicy`, so landing exactly on a zone's
    /// end reads as past it.
    private static func contains(_ time: TimeInterval, in zone: PlaybackSkipZone) -> Bool {
        zone.startTime <= time && time < zone.endTime
    }
}
