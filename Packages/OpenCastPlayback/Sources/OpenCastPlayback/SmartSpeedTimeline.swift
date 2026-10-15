import Foundation

/// Maps between the original episode clock and the shortened Smart Speed
/// clock. Long pauses are trimmed to `keptPause`, split evenly around the
/// cut so neither the end of one phrase nor the start of the next is clipped.
nonisolated struct SmartSpeedTimeline: Sendable, Equatable {
    struct Segment: Sendable, Equatable {
        let originalStart: TimeInterval
        let compositionStart: TimeInterval
        let duration: TimeInterval

        var originalEnd: TimeInterval { originalStart + duration }
        var compositionEnd: TimeInterval { compositionStart + duration }
    }

    let originalDuration: TimeInterval
    let segments: [Segment]

    var compositionDuration: TimeInterval {
        segments.last?.compositionEnd ?? 0
    }

    var timeSaved: TimeInterval {
        originalDuration - compositionDuration
    }

    init(
        silences: [ClosedRange<TimeInterval>],
        originalDuration: TimeInterval,
        keptPause: TimeInterval = 0.2,
        minimumPause: TimeInterval = 0.3
    ) {
        self.originalDuration = originalDuration
        var segments: [Segment] = []
        var cursor: TimeInterval = 0
        var compositionCursor: TimeInterval = 0

        for silence in silences.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            let length = silence.upperBound - silence.lowerBound
            guard length >= minimumPause, length > keptPause else { continue }
            let cutStart = silence.lowerBound + keptPause / 2
            let cutEnd = min(silence.upperBound - keptPause / 2, originalDuration)
            guard cutStart > cursor, cutEnd > cutStart else { continue }

            segments.append(Segment(
                originalStart: cursor,
                compositionStart: compositionCursor,
                duration: cutStart - cursor
            ))
            compositionCursor += cutStart - cursor
            cursor = cutEnd
        }

        if originalDuration > cursor {
            segments.append(Segment(
                originalStart: cursor,
                compositionStart: compositionCursor,
                duration: originalDuration - cursor
            ))
        }
        self.segments = segments
    }

    /// The first removed span starting at or after `time`, on the original
    /// clock.
    func nextCut(after time: TimeInterval) -> (start: TimeInterval, end: TimeInterval)? {
        zip(segments, segments.dropFirst())
            .first { before, _ in before.originalEnd >= time }
            .map { before, after in (before.originalEnd, after.originalStart) }
    }

    /// A time inside a removed pause maps to the cut point that replaced it.
    func compositionTime(forOriginal time: TimeInterval) -> TimeInterval {
        guard let segment = lastSegment(where: { $0.originalStart <= time }) else { return 0 }
        return segment.compositionStart + min(time - segment.originalStart, segment.duration)
    }

    func originalTime(forComposition time: TimeInterval) -> TimeInterval {
        guard let segment = lastSegment(where: { $0.compositionStart <= time }) else { return 0 }
        return segment.originalStart + min(time - segment.compositionStart, segment.duration)
    }

    /// Binary search for the last segment satisfying a predicate that is
    /// true for a prefix of `segments`.
    private func lastSegment(where isAtOrBefore: (Segment) -> Bool) -> Segment? {
        var lo = 0
        var hi = segments.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if isAtOrBefore(segments[mid]) {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo == 0 ? nil : segments[lo - 1]
    }
}
