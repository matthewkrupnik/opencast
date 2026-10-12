import Foundation

/// Port of the worker's `coalescing.rs`. Above 1,399 segments the model's id
/// discipline breaks down, so segments are greedily merged into units that
/// get zero-based ids; the remap translates unit ids back to original ids.
nonisolated enum TranscriptAnalysisCoalescer {
    static let triggerSegmentCount = 1_399
    static let maximumUnitCount = 2_400
    static let minimumUnitSpan: TimeInterval = 5
    static let unitJoinCharacterLimit = 700
    static let gapBreak: TimeInterval = 1.5

    struct UnitRemap: Equatable, Sendable {
        var originalStartID: Int
        var originalEndID: Int
    }

    struct Prepared: Sendable {
        var segments: [EpisodeTranscriptAnalysisAPISegment]
        /// nil for the raw path; otherwise unit index → original ids.
        var remap: [UnitRemap]?
    }

    enum Failure: Error, Equatable {
        case tooManyUnits
    }

    static func prepare(_ segments: [EpisodeTranscriptAnalysisAPISegment]) throws -> Prepared {
        guard segments.count > triggerSegmentCount else {
            return Prepared(segments: segments, remap: nil)
        }
        let (units, remap) = coalesce(segments)
        guard units.count <= maximumUnitCount else {
            throw Failure.tooManyUnits
        }
        return Prepared(segments: units, remap: remap)
    }

    static func coalesce(
        _ segments: [EpisodeTranscriptAnalysisAPISegment]
    ) -> ([EpisodeTranscriptAnalysisAPISegment], [UnitRemap]) {
        guard let first = segments.first else {
            return ([], [])
        }
        var units: [EpisodeTranscriptAnalysisAPISegment] = []
        var remap: [UnitRemap] = []
        var current = OpenUnit(first)
        for segment in segments.dropFirst() {
            if current.closes(before: segment) {
                let (unit, mapping) = current.close(id: units.count)
                units.append(unit)
                remap.append(mapping)
                current = OpenUnit(segment)
            } else {
                current.extend(segment)
            }
        }
        let (unit, mapping) = current.close(id: units.count)
        units.append(unit)
        remap.append(mapping)
        return (units, remap)
    }

    private struct OpenUnit {
        var segment: EpisodeTranscriptAnalysisAPISegment
        var joinedCharacterCount: Int
        var firstOriginalID: Int
        var lastOriginalID: Int
        var lastRawEnd: TimeInterval

        init(_ segment: EpisodeTranscriptAnalysisAPISegment) {
            self.segment = EpisodeTranscriptAnalysisAPISegment(id: 0, start: segment.start, end: segment.end, text: segment.text)
            joinedCharacterCount = segment.text.unicodeScalars.count
            firstOriginalID = segment.id
            lastOriginalID = segment.id
            lastRawEnd = segment.end
        }

        func closes(before next: EpisodeTranscriptAnalysisAPISegment) -> Bool {
            lastRawEnd - segment.start >= minimumUnitSpan
                || joinedCharacterCount + 1 + next.text.unicodeScalars.count > unitJoinCharacterLimit
                || next.start - lastRawEnd > gapBreak
        }

        mutating func extend(_ next: EpisodeTranscriptAnalysisAPISegment) {
            lastOriginalID = next.id
            lastRawEnd = next.end
            segment.end = next.end
            segment.text += " " + next.text
            joinedCharacterCount += 1 + next.text.unicodeScalars.count
        }

        func close(id: Int) -> (EpisodeTranscriptAnalysisAPISegment, UnitRemap) {
            var unit = segment
            unit.id = id
            unit.end = max(unit.end, unit.start)
            return (unit, UnitRemap(originalStartID: firstOriginalID, originalEndID: lastOriginalID))
        }
    }
}
