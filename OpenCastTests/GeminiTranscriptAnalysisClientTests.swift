import CryptoKit
import Foundation
import Testing
@testable import OpenCast

/// Vectors ported from `Server/TranscriptAnalysisWorker`, plus the in-app
/// client's retry escalation.
@Suite("Gemini Chapters & Summary")
struct GeminiTranscriptAnalysisClientTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    @Test("The built prompt matches the worker's golden sha256 pin")
    func goldenPromptSHA256() throws {
        let fixtureURL = Self.repoRoot.appending(path: "Server/TranscriptAnalysisWorker/tests/fixtures/golden_prompt_request.json")
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        let transcript = try #require(fixture["transcript"] as? [String: Any])
        let segments = try #require(fixture["segments"] as? [[String: Any]]).map {
            EpisodeTranscriptAnalysisAPISegment(
                id: $0["id"] as! Int,
                start: ($0["start"] as! NSNumber).doubleValue,
                end: ($0["end"] as! NSNumber).doubleValue,
                text: $0["text"] as! String
            )
        }
        let request = Self.request(
            segments: segments,
            episodeID: fixture["episode_id"] as! String,
            podcastID: fixture["podcast_id"] as! String,
            episodeTitle: fixture["episode_title"] as? String,
            podcastTitle: fixture["podcast_title"] as? String,
            languageCode: transcript["language_code"] as! String,
            audioDuration: (transcript["audio_duration"] as! NSNumber).doubleValue
        )

        let prompt = TranscriptAnalysisV2Prompt.build(request, segments: request.segments)

        let digest = SHA256.hash(data: Data(prompt.utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(digest == "0e6580614ac391a079b6ac26b480dbea538323829351c0773c6f42c26a6a85db")
        #expect(prompt.contains("[0 | 0.000-10.000]"))
    }

    @Test("The bundled prompts are byte-identical to the worker sources")
    func promptsPinnedToServerSources() throws {
        let adSource = try Data(contentsOf: Self.repoRoot.appending(path: "Server/AdAnalysisWorker/src/promo_v3_prompt.txt"))
        #expect(Data(AdAnalysisV3Payload.instructions.utf8) == adSource)

        let rust = try String(contentsOf: Self.repoRoot.appending(path: "Server/TranscriptAnalysisWorker/src/prompt.rs"), encoding: .utf8)
        let start = try #require(rust.range(of: #"const TRANSCRIPT_ANALYSIS_V2_RULES: &str = r#""#))
        let end = try #require(rust.range(of: "\"#;", range: start.upperBound..<rust.endIndex))
        #expect(TranscriptAnalysisV2Prompt.rules == String(rust[start.upperBound..<end.lowerBound]))
    }

    @Test("Overlapping chapters and invented ids are hard failures; gaps are warnings")
    func validatorSeverities() {
        let segments = Self.segments(count: 6)
        func validate(_ chapters: [(Int, Int)]) -> Result<TranscriptAnalysisV2Validator.Validated, TranscriptAnalysisV2Validator.Violations> {
            TranscriptAnalysisV2Validator.validate(Self.output(chapters), segments: segments, audioDuration: 600)
        }

        guard case .success(let gap) = validate([(0, 1), (3, 5)]) else {
            Issue.record("A coverage gap must not fail the run")
            return
        }
        #expect(gap.warnings.contains { $0.hasPrefix("coverage_gap") })
        #expect(gap.chapters.map(\.startTime) == [0, 300])

        guard case .failure(let overlap) = validate([(0, 3), (2, 5)]) else {
            Issue.record("Overlap must be hard")
            return
        }
        #expect(overlap.messages.contains { $0.hasPrefix("chapter_overlap") })

        guard case .failure(let invented) = validate([(0, 99)]) else {
            Issue.record("An invented id must be hard")
            return
        }
        #expect(invented.messages.contains { $0.hasPrefix("id_discipline") })
    }

    @Test("URL-shaped text anywhere is a hard failure")
    func urlsAreHard() {
        #expect(TranscriptAnalysisV2Validator.containsURLShape("visit example.com/deal"))
        #expect(TranscriptAnalysisV2Validator.containsURLShape("www.example"))
        #expect(!TranscriptAnalysisV2Validator.containsURLShape("A story about .com/ culture"))
        var output = Self.output([(0, 5)])
        output.summary.summary = "Go to https://example.com now."
        guard case .failure(let violations) = TranscriptAnalysisV2Validator.validate(output, segments: Self.segments(count: 6), audioDuration: 600) else {
            Issue.record("Expected a URL violation")
            return
        }
        #expect(violations.messages.contains { $0.hasPrefix("no_urls") })
    }

    @Test("Dense transcripts coalesce into units and remap to original ids")
    func coalescingRemapsToOriginalIDs() throws {
        let segments = (0..<2_000).map {
            EpisodeTranscriptAnalysisAPISegment(id: 1_000 + $0, start: Double($0), end: Double($0) + 1, text: "word")
        }
        let prepared = try TranscriptAnalysisCoalescer.prepare(segments)
        let remap = try #require(prepared.remap)
        #expect(prepared.segments.count == remap.count)
        #expect(prepared.segments.count < segments.count)
        #expect(prepared.segments.map(\.id) == Array(0..<prepared.segments.count))
        #expect(remap.first?.originalStartID == 1_000)
        #expect(remap.last?.originalEndID == 2_999)

        let lastUnit = prepared.segments.count - 1
        var output = Self.output([(0, lastUnit)])
        output.summary.claims = [.init(text: "A claim.", evidenceSegmentID: 1)]
        guard case .success(let validated) = TranscriptAnalysisV2Validator.validate(
            output,
            segments: segments,
            prepared: prepared,
            audioDuration: 2_000
        ) else {
            Issue.record("Expected the coalesced output to validate")
            return
        }
        #expect(validated.chapters.first?.startSegmentID == 1_000)
        #expect(validated.chapters.first?.endSegmentID == 2_999)
        #expect(validated.summary.claims.first?.evidenceSegmentID == remap[1].originalStartID)
    }

    @Test("Short transcripts keep the raw path")
    func shortTranscriptsAreNotCoalesced() throws {
        let prepared = try TranscriptAnalysisCoalescer.prepare(Self.segments(count: 1_399))
        #expect(prepared.remap == nil)
    }

    @Test("An invalid first answer escalates to high thinking and then succeeds")
    func invalidAnswerEscalatesToHighThinking() async throws {
        let valid = try Self.answerJSON(Self.output([(0, 5)]))
        let transport = GeminiTestTransport([
            GeminiTestTransport.answer(#"{"chapters": "not an array"}"#),
            GeminiTestTransport.answer(valid)
        ])
        let client = GeminiTranscriptAnalysisClient(gemini: .testing(transport))

        let outcome = try await client.analyze(Self.request(segments: Self.segments(count: 6)))

        guard case .completed(let response) = outcome else {
            Issue.record("Expected a completed response")
            return
        }
        #expect(response.policy == "transcript_analysis_v2")
        #expect(response.schemaVersion == 1)
        #expect(response.warnings.contains { $0.hasPrefix("invalid_model_output_retried_high") })
        let levels = try transport.requests.map {
            ((try GeminiTestTransport.requestBody($0)["generationConfig"] as? [String: Any])?["thinkingConfig"] as? [String: String])?["thinkingLevel"]
        }
        #expect(levels == ["medium", "high"])
    }

    @Test("A hard quota defers like a cap")
    func quotaIsCapExceeded() async throws {
        let transport = GeminiTestTransport([
            GeminiTestTransport.error(status: 429, statusText: "RESOURCE_EXHAUSTED", message: "Quota exceeded for billing account.")
        ])
        let client = GeminiTranscriptAnalysisClient(gemini: .testing(transport))

        do {
            _ = try await client.analyze(Self.request(segments: Self.segments(count: 6)))
            Issue.record("Expected a quota error")
        } catch let error as EpisodeTranscriptAnalysisHTTPError {
            #expect(error.isCapExceeded)
        }
    }

    // MARK: Fixtures

    static func segments(count: Int) -> [EpisodeTranscriptAnalysisAPISegment] {
        (0..<count).map {
            EpisodeTranscriptAnalysisAPISegment(id: $0, start: Double($0) * 100, end: Double($0 + 1) * 100, text: "Segment \($0).")
        }
    }

    static func output(_ chapters: [(Int, Int)]) -> TranscriptAnalysisV2Validator.ModelOutput {
        TranscriptAnalysisV2Validator.ModelOutput(
            chapters: chapters.enumerated().map {
                .init(title: "Chapter \($0.offset)", startSegmentID: $0.element.0, endSegmentID: $0.element.1, confidence: 0.8)
            },
            summary: .init(
                summary: "An episode about segments.",
                oneLineDescription: "Segments, discussed",
                claims: [.init(text: "Segments exist.", evidenceSegmentID: 0)]
            )
        )
    }

    static func request(
        segments: [EpisodeTranscriptAnalysisAPISegment],
        episodeID: String = "episode",
        podcastID: String = "https://example.com/feed.xml",
        episodeTitle: String? = "Episode",
        podcastTitle: String? = "Podcast",
        languageCode: String = "en-US",
        audioDuration: TimeInterval = 600
    ) -> EpisodeTranscriptAnalysisAPIRequest {
        EpisodeTranscriptAnalysisAPIRequest(
            schemaVersion: 1,
            requestID: "request",
            episodeID: episodeID,
            podcastID: podcastID,
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            allowShared: false,
            transcript: EpisodeTranscriptAnalysisAPITranscriptMetadata(
                languageCode: languageCode,
                audioDuration: audioDuration,
                fingerprint: "fingerprint",
                updatedAt: Date(timeIntervalSince1970: 0),
                state: "completed",
                segmentCount: segments.count
            ),
            segments: segments
        )
    }

    private static func answerJSON(_ output: TranscriptAnalysisV2Validator.ModelOutput) throws -> String {
        let object: [String: Any] = [
            "chapters": output.chapters.map {
                ["title": $0.title, "start_segment_id": $0.startSegmentID, "end_segment_id": $0.endSegmentID, "confidence": $0.confidence]
            },
            "summary": [
                "summary": output.summary.summary,
                "one_line_description": output.summary.oneLineDescription,
                "claims": output.summary.claims.map { ["text": $0.text, "evidence_segment_id": $0.evidenceSegmentID] }
            ]
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}
