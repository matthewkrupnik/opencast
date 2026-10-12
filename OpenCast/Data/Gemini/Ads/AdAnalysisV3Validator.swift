import Foundation
import OpenCastTranscription

/// Port of the worker's `promo_v3` validation. Boundary receipts are checked
/// at BOTH submitted boundaries; an interior promotional quote never moves a
/// span. Times come from the submitted segments, never from the model.
nonisolated enum AdAnalysisV3Validator {
    static let maximumBreakSeconds: TimeInterval = 600
    static let maximumBreaksPerWindow = 32
    /// Short mixed show/ad boundary segments are included whole; longer ones
    /// trim inward.
    static let maximumMixedBoundarySeconds: TimeInterval = 10
    static let adBudgetEpisodeFraction = 0.40
    static let adBudgetFloorSeconds: TimeInterval = 600
    static let declaredDurationMinimumFraction = 0.5
    static let autoSkipConfidence = 0.8

    struct Validation: Equatable {
        var spans: [EpisodeAdAnalysisAPIAdSpan] = []
        /// Machine-readable, ids only.
        var issues: [String] = []
        /// Conservative boundary reductions, not discarded candidates.
        var notices: [String] = []

        var isComplete: Bool {
            issues.isEmpty
        }
    }

    static func validate(_ request: EpisodeAdAnalysisAPIRequest, _ output: AdAnalysisV3Output) -> Validation {
        validate(request, output, entireRequest: true)
    }

    static func validateWindow(_ request: EpisodeAdAnalysisAPIRequest, _ output: AdAnalysisV3Output) -> Validation {
        validate(request, output, entireRequest: false)
    }

    /// A repair may not pass validation by erasing already verified breaks or
    /// lowering their automatic-skip confidence.
    static func preservesVerifiedBreaks(before: Validation, after: Validation) -> Bool {
        before.spans.allSatisfy { old in
            after.spans.contains { new in
                new.startTime <= old.startTime + 0.001
                    && new.endTime >= old.endTime - 0.001
                    && new.confidence >= min(old.confidence, autoSkipConfidence)
            }
        }
    }

    static func normalizedTokens(_ text: String) -> [String] {
        OpenCastAdBoundaryResolver.normalizedTokens(text)
    }

    /// The receipt must occur exactly once (≤ 32 normalized words). Returns
    /// (start token, end token, token count of the segment).
    static func receiptPosition(text: String, quote: String) -> (start: Int, end: Int, count: Int)? {
        guard quote.utf8.count <= 2_048 else {
            return nil
        }
        let words = normalizedTokens(text)
        let receipt = normalizedTokens(quote)
        guard !receipt.isEmpty, receipt.count <= 32, receipt.count <= words.count else {
            return nil
        }
        var matches: [Int] = []
        for start in 0...(words.count - receipt.count) where Array(words[start..<(start + receipt.count)]) == receipt {
            matches.append(start)
        }
        guard matches.count == 1 else {
            return nil
        }
        return (matches[0], matches[0] + receipt.count, words.count)
    }

    static func episodeAdBudgetSeconds(_ transcript: EpisodeAdAnalysisAPITranscriptMetadata) -> TimeInterval {
        let audio = transcript.audioDuration
        func base(_ runtime: TimeInterval) -> TimeInterval {
            max(adBudgetEpisodeFraction * runtime, adBudgetFloorSeconds)
        }
        if let declared = transcript.declaredDuration,
           declared.isFinite, audio.isFinite,
           declared < audio,
           declared >= declaredDurationMinimumFraction * audio {
            return base(declared) + (audio - declared)
        }
        return base(audio)
    }

    private static func validate(
        _ request: EpisodeAdAnalysisAPIRequest,
        _ output: AdAnalysisV3Output,
        entireRequest: Bool
    ) -> Validation {
        var result = Validation()
        let segments = request.segments
        let cap = maximumBreaksPerWindow * (entireRequest ? AdAnalysisV3Windowing.windowCount(segments.count) : 1)
        guard output.spans.count <= cap else {
            result.issues.append("v3_too_many_breaks")
            return result
        }
        let positions = Dictionary(segments.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })

        for span in output.spans {
            let tag = "\(span.startSegmentID)-\(span.endSegmentID)"
            guard let kind = EpisodeAdAnalysisSpanKind(rawValue: span.kind), kind != .unknown else {
                result.issues.append("v3_invalid_kind:\(tag)")
                continue
            }
            guard let start = positions[span.startSegmentID], let end = positions[span.endSegmentID] else {
                result.issues.append("v3_unknown_boundary:\(tag)")
                continue
            }
            let label = span.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard end >= start,
                  span.confidence.isFinite,
                  (0...1).contains(span.confidence),
                  !label.isEmpty,
                  span.label.utf8.count <= 256
            else {
                result.issues.append("v3_invalid_span:\(tag)")
                continue
            }
            guard let startReceipt = receiptPosition(text: segments[start].text, quote: span.startQuote),
                  let endReceipt = receiptPosition(text: segments[end].text, quote: span.endQuote)
            else {
                result.issues.append("v3_boundary_receipt_mismatch:\(tag)")
                continue
            }
            let cue = normalizedTokens(span.evidenceQuote)
            let content = normalizedTokens(segments[start...end].map(\.text).joined(separator: " "))
            guard (2...32).contains(cue.count), contains(content, cue) else {
                result.issues.append("v3_evidence_mismatch:\(tag)")
                continue
            }

            func isShortBoundary(_ index: Int) -> Bool {
                let duration = segments[index].end - segments[index].start
                return duration.isFinite && duration > 0 && duration <= maximumMixedBoundarySeconds
            }
            let mixedStart = startReceipt.start > 0
            let mixedEnd = endReceipt.end < endReceipt.count
            let safeStart = start + (mixedStart && !isShortBoundary(start) ? 1 : 0)
            let safeEnd = end - (mixedEnd && !isShortBoundary(end) ? 1 : 0)
            guard safeEnd >= 0, safeStart <= safeEnd else {
                result.issues.append("v3_mixed_boundary_unresolvable:\(tag)")
                continue
            }
            if safeStart != start || safeEnd != end {
                result.notices.append("v3_boundary_trimmed:\(tag)->\(segments[safeStart].id)-\(segments[safeEnd].id)")
            }
            if (mixedStart && safeStart == start) || (mixedEnd && safeEnd == end) {
                result.notices.append("v3_short_mixed_boundary_included:\(tag)")
            }
            let first = segments[safeStart]
            let last = segments[safeEnd]
            guard last.end > first.start, last.end - first.start <= maximumBreakSeconds else {
                result.issues.append("v3_break_duration:\(tag)")
                continue
            }
            // A safety alarm, not silent censoring: repair or fail.
            if entireRequest, Double(safeEnd - safeStart + 1) > Double(segments.count) * 0.8 {
                result.issues.append("v3_covers_request:\(tag)")
                continue
            }
            result.spans.append(EpisodeAdAnalysisAPIAdSpan(
                kind: kind,
                label: label,
                startSegmentID: first.id,
                endSegmentID: last.id,
                startTime: first.start,
                endTime: last.end,
                confidence: span.confidence,
                evidenceQuote: span.evidenceQuote.trimmingCharacters(in: .whitespacesAndNewlines),
                startBoundary: OpenCastAdBoundary(segmentID: span.startSegmentID, quote: span.startQuote),
                endBoundary: OpenCastAdBoundary(segmentID: span.endSegmentID, quote: span.endQuote)
            ))
        }

        // Reconcile overlapping windows only across overlapping or truly
        // adjacent segments, never bridging unclassified show content. The
        // two confidence tiers merge independently.
        result.spans.sort(by: chronological)
        var tiers: [[EpisodeAdAnalysisAPIAdSpan]] = [[], []]
        for span in result.spans {
            let tier = span.confidence >= autoSkipConfidence ? 1 : 0
            if var last = tiers[tier].last,
               let spanStart = positions[span.startSegmentID],
               let lastEnd = positions[last.endSegmentID],
               spanStart <= lastEnd + 1,
               span.startTime - last.endTime <= 1 {
                last.startBoundary = mergedBoundary(last.startBoundary, span.startBoundary, segments: segments, isStart: true)
                last.endBoundary = mergedBoundary(last.endBoundary, span.endBoundary, segments: segments, isStart: false)
                if span.endTime > last.endTime {
                    last.endTime = span.endTime
                    last.endSegmentID = span.endSegmentID
                }
                last.confidence = min(last.confidence, span.confidence)
                tiers[tier][tiers[tier].count - 1] = last
                continue
            }
            tiers[tier].append(span)
        }
        result.spans = (tiers[0] + tiers[1]).sorted(by: chronological)

        if entireRequest, result.spans.contains(where: { span in
            guard let start = positions[span.startSegmentID], let end = positions[span.endSegmentID] else {
                return false
            }
            return Double(end - start + 1) > Double(segments.count) * 0.8
        }) {
            result.issues.append("v3_merged_covers_request")
        }
        if result.spans.contains(where: { $0.endTime - $0.startTime > maximumBreakSeconds }) {
            result.issues.append("v3_merged_break_duration")
        }
        // Count each second once even where the tiers overlap.
        var coveredEnd = -Double.infinity
        var duration: TimeInterval = 0
        for span in result.spans {
            duration += max(0, span.endTime - max(span.startTime, coveredEnd))
            coveredEnd = max(coveredEnd, span.endTime)
        }
        if entireRequest, duration > episodeAdBudgetSeconds(request.transcript) {
            result.issues.append("v3_ad_budget_exceeded")
        }
        return result
    }

    private static func chronological(_ lhs: EpisodeAdAnalysisAPIAdSpan, _ rhs: EpisodeAdAnalysisAPIAdSpan) -> Bool {
        lhs.startTime != rhs.startTime ? lhs.startTime < rhs.startTime : lhs.endTime < rhs.endTime
    }

    private static func contains(_ words: [String], _ phrase: [String]) -> Bool {
        guard !phrase.isEmpty, phrase.count <= words.count else {
            return false
        }
        return (0...(words.count - phrase.count)).contains { Array(words[$0..<($0 + phrase.count)]) == phrase }
    }

    /// Keep the outermost text anchor; drop both when either can't be located.
    private static func mergedBoundary(
        _ current: OpenCastAdBoundary?,
        _ incoming: OpenCastAdBoundary?,
        segments: [EpisodeAdAnalysisAPISegment],
        isStart: Bool
    ) -> OpenCastAdBoundary? {
        func position(_ anchor: OpenCastAdBoundary?) -> (Int, Int)? {
            guard let anchor,
                  let index = segments.firstIndex(where: { $0.id == anchor.segmentID }),
                  let receipt = receiptPosition(text: segments[index].text, quote: anchor.quote)
            else {
                return nil
            }
            return (index, isStart ? receipt.start : receipt.end)
        }
        guard let old = position(current), let new = position(incoming) else {
            return nil
        }
        let newIsOuter = isStart ? new < old : new > old
        return newIsOuter ? incoming : current
    }
}
