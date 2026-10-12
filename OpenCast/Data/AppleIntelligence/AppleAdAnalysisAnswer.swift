import FoundationModels

/// The `promo_ad_breaks_v3` answer for Foundation Models guided generation.
/// Property names are the snake_case fields the v3 prompt names, so the
/// schema shown to the model matches its instructions.
@Generable
nonisolated struct AppleAdAnalysisAnswer: Equatable, Sendable {
    @Generable
    nonisolated struct Span: Equatable, Sendable {
        @Guide(.anyOf(["host_read_ad", "inserted_ad", "house_or_network_promo"]))
        var kind: String
        var label: String
        var start_segment_id: Int
        var end_segment_id: Int
        var confidence: Double
        var evidence_quote: String
        var start_quote: String
        var end_quote: String
    }

    var spans: [Span]

    var output: AdAnalysisV3Output {
        AdAnalysisV3Output(spans: spans.map { span in
            AdAnalysisV3Output.Span(
                kind: span.kind,
                label: span.label,
                startSegmentID: span.start_segment_id,
                endSegmentID: span.end_segment_id,
                confidence: span.confidence,
                evidenceQuote: span.evidence_quote,
                startQuote: span.start_quote,
                endQuote: span.end_quote
            )
        })
    }
}
