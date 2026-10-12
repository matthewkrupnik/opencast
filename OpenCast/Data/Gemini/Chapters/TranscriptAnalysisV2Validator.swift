import Foundation

/// Port of the worker's `transcript_analysis_v2` output validation. Hard
/// violations fail the attempt (chapters are a partition, so one bad chapter
/// invalidates the navigation); soft ones become response warnings.
nonisolated enum TranscriptAnalysisV2Validator {
    static let summaryMaxCharacters = 1_200
    static let oneLineMaxCharacters = 140
    static let claimRange = 1...12
    static let minimumChapterCap = 3
    static let secondsPerChapter: TimeInterval = 240

    struct ModelOutput: Decodable, Equatable {
        struct Chapter: Decodable, Equatable {
            var title: String
            var startSegmentID: Int
            var endSegmentID: Int
            var confidence: Double

            enum CodingKeys: String, CodingKey {
                case title
                case startSegmentID = "start_segment_id"
                case endSegmentID = "end_segment_id"
                case confidence
            }
        }

        struct Claim: Decodable, Equatable {
            var text: String
            var evidenceSegmentID: Int

            enum CodingKeys: String, CodingKey {
                case text
                case evidenceSegmentID = "evidence_segment_id"
            }
        }

        struct Summary: Decodable, Equatable {
            var summary: String
            var oneLineDescription: String
            var claims: [Claim]

            enum CodingKeys: String, CodingKey {
                case summary
                case oneLineDescription = "one_line_description"
                case claims
            }
        }

        var chapters: [Chapter]
        var summary: Summary
    }

    /// Hard violations, as `rule: detail` strings.
    struct Violations: Error, Equatable {
        var messages: [String]
    }

    struct Validated: Equatable {
        var chapters: [EpisodeTranscriptAnalysisAPIChapter]
        var summary: EpisodeTranscriptAnalysisAPISummary
        var warnings: [String]
    }

    static func maxChapters(duration: TimeInterval) -> Int {
        max(minimumChapterCap, Int((duration / secondsPerChapter).rounded(.up)))
    }

    /// Raw requests validate once. Coalesced requests must pass in unit space
    /// first, then are remapped and validated again against the raw segments,
    /// so no unit id can escape.
    static func validate(
        _ output: ModelOutput,
        segments: [EpisodeTranscriptAnalysisAPISegment],
        prepared: TranscriptAnalysisCoalescer.Prepared,
        audioDuration: TimeInterval
    ) -> Result<Validated, Violations> {
        guard let remap = prepared.remap else {
            return validate(output, segments: segments, audioDuration: audioDuration)
        }
        if case .failure(let violations) = validate(output, segments: prepared.segments, audioDuration: audioDuration) {
            return .failure(violations)
        }
        guard let mapped = remapped(output, remap) else {
            return .failure(Violations(messages: ["id_discipline: validated unit id could not be remapped"]))
        }
        return validate(mapped, segments: segments, audioDuration: audioDuration)
    }

    static func validate(
        _ output: ModelOutput,
        segments: [EpisodeTranscriptAnalysisAPISegment],
        audioDuration: TimeInterval
    ) -> Result<Validated, Violations> {
        guard !segments.isEmpty else {
            return .failure(Violations(messages: ["segments_shape: no segments"]))
        }
        var hard: [String] = []
        var warnings: [String] = []
        let indexByID = Dictionary(segments.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })

        if output.chapters.isEmpty {
            hard.append("chapters_shape: chapters empty")
        }
        let cap = maxChapters(duration: audioDuration)
        if output.chapters.count > cap {
            hard.append("chapter_count_cap: \(output.chapters.count) chapters exceeds cap \(cap)")
        }

        var chapters: [EpisodeTranscriptAnalysisAPIChapter] = []
        var previousEnd: Int?
        for (index, chapter) in output.chapters.enumerated() {
            let start = indexByID[chapter.startSegmentID]
            let end = indexByID[chapter.endSegmentID]
            if start == nil {
                hard.append("id_discipline: chapter \(index) start_segment_id \(chapter.startSegmentID) is not a submitted id")
            }
            if end == nil {
                hard.append("id_discipline: chapter \(index) end_segment_id \(chapter.endSegmentID) is not a submitted id")
            }
            if let start, let end {
                if end < start {
                    hard.append("chapter_order: chapter \(index) ends before it starts")
                } else {
                    if let previousEnd, start <= previousEnd {
                        hard.append("chapter_overlap: chapter \(index) overlaps chapter \(index - 1)")
                    } else if let previousEnd, start != previousEnd + 1 {
                        warnings.append("coverage_gap: gap of \(start - previousEnd - 1) segments before chapter \(index)")
                    } else if previousEnd == nil, start != 0 {
                        warnings.append("coverage_gap: first chapter starts at segment \(chapter.startSegmentID), not \(segments[0].id)")
                    }
                    previousEnd = end
                }
            }
            let title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
                hard.append("chapter_title: chapter \(index) title missing or empty")
            } else if containsURLShape(title) {
                hard.append("no_urls: chapter \(index) title contains a URL-shaped string")
            }
            if !chapter.confidence.isFinite || !(0...1).contains(chapter.confidence) {
                hard.append("chapter_confidence: chapter \(index) confidence \(chapter.confidence)")
            }
            if let start, let end, end >= start {
                chapters.append(EpisodeTranscriptAnalysisAPIChapter(
                    title: title,
                    startSegmentID: chapter.startSegmentID,
                    endSegmentID: chapter.endSegmentID,
                    startTime: segments[start].start,
                    endTime: segments[end].end,
                    confidence: chapter.confidence
                ))
            }
        }
        if let previousEnd, previousEnd != segments.count - 1 {
            warnings.append("coverage_gap: last chapter ends at segment \(segments[previousEnd].id), transcript ends at segment \(segments[segments.count - 1].id)")
        }

        let summary = output.summary
        let summaryText = summary.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if summaryText.isEmpty {
            hard.append("summary_text: summary missing or empty")
        } else {
            if summary.summary.unicodeScalars.count > summaryMaxCharacters {
                hard.append("summary_length: summary is \(summary.summary.unicodeScalars.count) chars")
            }
            if containsURLShape(summary.summary) {
                hard.append("no_urls: summary contains a URL-shaped string")
            }
        }
        let oneLine = summary.oneLineDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if oneLine.isEmpty {
            hard.append("one_line_text: one_line_description missing or empty")
        } else {
            if summary.oneLineDescription.unicodeScalars.count > oneLineMaxCharacters {
                hard.append("one_line_length: one_line_description is \(summary.oneLineDescription.unicodeScalars.count) chars")
            }
            if containsURLShape(summary.oneLineDescription) {
                hard.append("no_urls: one_line_description contains a URL-shaped string")
            }
        }
        if !claimRange.contains(summary.claims.count) {
            hard.append("claims_count: claims count \(summary.claims.count)")
        } else {
            for (index, claim) in summary.claims.enumerated() {
                if indexByID[claim.evidenceSegmentID] == nil {
                    hard.append("id_discipline: claim \(index) evidence_segment_id \(claim.evidenceSegmentID) is not a submitted id")
                }
                if claim.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hard.append("claim_text: claim \(index) text missing or empty")
                } else if containsURLShape(claim.text) {
                    hard.append("no_urls: claim \(index) text contains a URL-shaped string")
                }
            }
        }

        guard hard.isEmpty else {
            return .failure(Violations(messages: hard))
        }
        return .success(Validated(
            chapters: chapters,
            summary: EpisodeTranscriptAnalysisAPISummary(
                summary: summaryText,
                oneLineDescription: oneLine,
                claims: summary.claims.map {
                    EpisodeTranscriptAnalysisAPIClaim(
                        text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                        evidenceSegmentID: $0.evidenceSegmentID
                    )
                }
            ),
            warnings: warnings
        ))
    }

    /// Scheme prefixes, `www.`, or a bare `label.tld/`. Summaries render in
    /// the app and the transcript is untrusted, so URL-shaped output is hard.
    static func containsURLShape(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("http://") || lower.contains("https://") || lower.contains("www.") {
            return true
        }
        for suffix in [".com/", ".net/", ".org/", ".io/", ".co/", ".ly/", ".gg/"] {
            var searchRange = lower.startIndex..<lower.endIndex
            while let found = lower.range(of: suffix, range: searchRange) {
                if found.lowerBound > lower.startIndex {
                    let previous = lower[lower.index(before: found.lowerBound)]
                    if previous.isASCII && (previous.isLetter || previous.isNumber) || previous == "-" {
                        return true
                    }
                }
                searchRange = found.upperBound..<lower.endIndex
            }
        }
        return false
    }

    private static func remapped(_ output: ModelOutput, _ remap: [TranscriptAnalysisCoalescer.UnitRemap]) -> ModelOutput? {
        func unit(_ id: Int) -> TranscriptAnalysisCoalescer.UnitRemap? {
            remap.indices.contains(id) ? remap[id] : nil
        }
        var mapped = output
        for index in mapped.chapters.indices {
            guard let start = unit(mapped.chapters[index].startSegmentID),
                  let end = unit(mapped.chapters[index].endSegmentID)
            else {
                return nil
            }
            mapped.chapters[index].startSegmentID = start.originalStartID
            mapped.chapters[index].endSegmentID = end.originalEndID
        }
        for index in mapped.summary.claims.indices {
            // A claim has one anchor; the unit's first raw id is it.
            guard let evidence = unit(mapped.summary.claims[index].evidenceSegmentID) else {
                return nil
            }
            mapped.summary.claims[index].evidenceSegmentID = evidence.originalStartID
        }
        return mapped
    }
}
