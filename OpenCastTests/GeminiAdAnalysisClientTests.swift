import Foundation
import Testing
@testable import OpenCast

/// Vectors ported from `Server/AdAnalysisWorker/tests/promo_v3.rs`, plus the
/// in-app client's transport and repair behaviour.
@Suite("Gemini ad analysis")
struct GeminiAdAnalysisClientTests {
    // MARK: Validator (ported vectors)

    @Test("Short real promos and repeated occurrences survive")
    func shortRealPromosAndRepeatedOccurrencesSurvive() {
        let result = AdAnalysisV3Validator.validate(Self.request(), output([shortSpan(306), shortSpan(646)]))
        #expect(result.isComplete, "\(result.issues)")
        #expect(result.spans.count == 2)
        #expect(abs(result.spans[0].endTime - result.spans[0].startTime - 6.8) < 1e-6)
        #expect(result.spans[0].startBoundary?.segmentID == 306)
        #expect(result.spans[0].endBoundary?.quote == "wherever you get podcasts")
    }

    @Test("A wrong but existing start id cannot borrow an interior receipt")
    func wrongStartIDCannotBorrowInteriorReceipt() {
        var span = shortSpan(306)
        span.startSegmentID = 106
        let result = AdAnalysisV3Validator.validate(Self.request(), output([span]))
        #expect(!result.isComplete)
        #expect(result.spans.isEmpty)
        #expect(result.issues == ["v3_boundary_receipt_mismatch:106-306"])
    }

    @Test("Long mixed boundary segments shrink inward without inventing word times")
    func longMixedBoundariesShrinkInward() {
        var request = Self.request()
        request.segments[1].text = "Back to boats. Listen to Harbor Stories wherever you get podcasts."
        request.segments[1].start = 590
        var span = shortSpan(306)
        span.endSegmentID = 398
        span.endQuote = "Subscribe today"
        let result = AdAnalysisV3Validator.validate(request, output([span]))
        #expect(result.isComplete, "\(result.issues)")
        #expect(result.spans[0].startSegmentID == 398)
        #expect(result.spans[0].startBoundary?.segmentID == 306)
        #expect(result.notices == ["v3_boundary_trimmed:306-398->398-398"])
        #expect(!AdAnalysisV3Validator.validate(request, output([shortSpan(306)])).isComplete)
    }

    @Test("Short mixed boundaries keep the entire ad opening and sign-off")
    func shortMixedBoundariesKeepWholeSegment() {
        var request = Self.request()
        request.segments[1].text = "Back to boats. Listen to Harbor Stories wherever you get podcasts. Our next boat."
        let result = AdAnalysisV3Validator.validate(request, output([shortSpan(306)]))
        #expect(result.isComplete, "\(result.issues)")
        #expect(result.spans[0].startTime == 600)
        #expect(result.spans[0].endTime == 606.8)
        #expect(result.notices == ["v3_short_mixed_boundary_included:306-306"])
    }

    @Test("A full-ad window is allowed but a full-ad request is an alarm")
    func fullAdWindowAllowedFullAdRequestAlarm() {
        var request = Self.request()
        request.segments = [request.segments[1]]
        request.transcript.segmentCount = 1
        #expect(AdAnalysisV3Validator.validateWindow(request, output([shortSpan(306)])).isComplete)
        #expect(!AdAnalysisV3Validator.validate(request, output([shortSpan(306)])).isComplete)
    }

    @Test("Duplicate confidence tiers keep auto-skip without double counting time")
    func duplicateConfidenceTiers() {
        var request = Self.request()
        request.transcript.audioDuration = 2_400
        let times: [(TimeInterval, TimeInterval)] = [(0, 600), (600, 1_000), (1_000, 1_010), (1_010, 1_800), (1_800, 1_806.8), (1_806.8, 2_400)]
        for (index, time) in times.enumerated() {
            request.segments[index].start = time.0
            request.segments[index].end = time.1
        }
        var low = shortSpan(306)
        low.confidence = 0.7
        let result = AdAnalysisV3Validator.validate(request, output([low, shortSpan(306)]))
        #expect(result.isComplete, "\(result.issues)")
        #expect(result.spans.contains { $0.confidence >= 0.8 })
    }

    @Test("Dynamically inserted pods fit the declared-runtime excess budget")
    func declaredRuntimeExcessBudget() {
        var request = Self.request()
        request.transcript.audioDuration = 3_600
        request.segments = (0..<180).map {
            EpisodeAdAnalysisAPISegment(
                id: $0,
                start: Double($0) * 20,
                end: Double($0 + 1) * 20,
                text: "Listen to Harbor Stories wherever you get podcasts."
            )
        }
        request.transcript.segmentCount = 180
        let pods = output([(0, 24), (60, 84), (120, 144)].map { start, end in
            var span = shortSpan(start)
            span.endSegmentID = end
            return span
        })
        #expect(AdAnalysisV3Validator.validate(request, pods).issues.contains("v3_ad_budget_exceeded"))
        request.transcript.declaredDuration = 2_400
        let declared = AdAnalysisV3Validator.validate(request, pods)
        #expect(declared.isComplete, "\(declared.issues)")
        #expect(declared.spans.count == 3)
        request.transcript.declaredDuration = 900
        #expect(AdAnalysisV3Validator.validate(request, pods).issues.contains("v3_ad_budget_exceeded"))
    }

    @Test("Contractions do not turn a valid cue into an incomplete analysis")
    func contractionsKeepValidCue() {
        var request = Self.request()
        request.segments[1].text = "I hope you'll tune in every Sunday for this week in tech."
        var span = shortSpan(306)
        span.startQuote = "I hope you'll tune in every Sunday"
        span.endQuote = "for this week in tech"
        span.evidenceQuote = request.segments[1].text
        #expect(AdAnalysisV3Validator.validate(request, output([span])).isComplete)
    }

    @Test("Local windows cover every segment with exact overlap")
    func windowsCoverEverySegment() {
        var request = Self.request()
        request.segments = (0..<6_000).map {
            EpisodeAdAnalysisAPISegment(id: $0 * 3, start: Double($0), end: Double($0) + 0.9, text: "Program content.")
        }
        request.transcript.segmentCount = 6_000
        let windows = AdAnalysisV3Windowing.windows(request)
        #expect(windows.count == 9)
        #expect(windows[0].segments.count == 800)
        #expect(windows[1].segments[0].id == 680 * 3)
        #expect(windows.last?.segments.last?.id == 5_999 * 3)
        for index in 0..<(windows.count - 1) {
            #expect(Array(windows[index].segments.suffix(120)) == Array(windows[index + 1].segments.prefix(120)))
        }
    }

    @Test("The model input has ids and text but no timestamps")
    func inputHasNoTimestamps() throws {
        let input = try JSONSerialization.jsonObject(with: Data(try AdAnalysisV3Payload.input(Self.request()).utf8)) as! [String: Any]
        let first = (input["segments"] as! [[String: Any]])[0]
        #expect(first["id"] as? Int == 106)
        #expect(first["start"] == nil)
        #expect(input["audio_duration"] == nil)
        #expect(input["episode"] as? String == "episode")
        #expect(AdAnalysisV3Payload.instructions.contains("untrusted"))
    }

    @Test("Strict parsing rejects truncated generations and counts thought tokens")
    func strictParsing() throws {
        let reply = GeminiTestTransport.answer(#"{"spans":[]}"#)
        let response = try JSONDecoder().decode(GeminiResponse.self, from: reply.body)
        #expect((try? response.strictAnswerText().get()) == #"{"spans":[]}"#)
        #expect(response.usageMetadata?.total == 22)
        let truncated = try JSONDecoder().decode(
            GeminiResponse.self,
            from: GeminiTestTransport.answer(#"{"spans":[]}"#, finishReason: "MAX_TOKENS").body
        )
        guard case .failure(.incompleteGeneration) = truncated.strictAnswerText() else {
            Issue.record("Expected an incomplete generation")
            return
        }
    }

    @Test("Receipt tokens match the native boundary resolver's Unicode contract")
    func unicodeTokens() {
        #expect(AdAnalysisV3Validator.normalizedTokens("CAFÉ—İ Ⅳ ² don't .org.") == ["café", "i̇", "ⅳ", "²", "don", "t", "org"])
    }

    // MARK: Client

    @Test("A clean answer becomes a completed v3 response with times and receipts")
    func cleanAnswerCompletes() async throws {
        let transport = GeminiTestTransport([.init(status: 200, body: try Self.answerBody([shortSpan(306), shortSpan(646)]))])
        let client = GeminiAdAnalysisClient(gemini: .testing(transport))

        let outcome = try await client.analyze(Self.request())

        guard case .completed(let response) = outcome else {
            Issue.record("Expected a completed response")
            return
        }
        #expect(response.policy == "promo_ad_breaks_v3")
        #expect(response.policyRevision == GeminiAdAnalysisClient.policyRevision)
        #expect(response.spans.map(\.startTime) == [600, 1_200])
        #expect(response.spans.allSatisfy { $0.startBoundary != nil && $0.endBoundary != nil })
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://gemini.test/v1beta/models/gemini-3.8-flash:generateContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
        let body = try GeminiTestTransport.requestBody(request)
        #expect((body["generationConfig"] as? [String: Any])?["thinkingConfig"] as? [String: String] == ["thinkingLevel": "medium"])
    }

    @Test("An invalid answer gets exactly one repair turn carrying the issues")
    func invalidAnswerIsRepairedOnce() async throws {
        var bad = shortSpan(306)
        bad.startSegmentID = 106
        let transport = GeminiTestTransport([
            .init(status: 200, body: try Self.answerBody([bad])),
            .init(status: 200, body: try Self.answerBody([shortSpan(306)]))
        ])
        let client = GeminiAdAnalysisClient(gemini: .testing(transport))

        guard case .completed(let response) = try await client.analyze(Self.request()) else {
            Issue.record("Expected a completed response")
            return
        }
        #expect(response.spans.count == 1)
        #expect(response.warnings.contains("v3_semantic_repair"))
        #expect(transport.requests.count == 2)
        let repair = try GeminiTestTransport.requestBody(transport.requests[1])
        let contents = try #require(repair["contents"] as? [[String: Any]])
        #expect(contents.map { $0["role"] as? String } == ["user", "model", "user"])
        let feedback = ((contents[2]["parts"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        #expect(feedback.contains("v3_boundary_receipt_mismatch:106-306"))
    }

    @Test("A repair that still fails reports an incomplete analysis")
    func failedRepairIsIncomplete() async throws {
        var bad = shortSpan(306)
        bad.startSegmentID = 106
        let transport = GeminiTestTransport([
            .init(status: 200, body: try Self.answerBody([bad])),
            .init(status: 200, body: try Self.answerBody([bad]))
        ])
        let client = GeminiAdAnalysisClient(gemini: .testing(transport))

        await #expect(throws: GeminiAdAnalysisClient.incomplete()) {
            _ = try await client.analyze(Self.request())
        }
    }

    @Test("A hard quota 429 is a cap deferral, not a failure")
    func hardQuotaIsCapExceeded() async throws {
        let transport = GeminiTestTransport([
            GeminiTestTransport.error(status: 429, statusText: "RESOURCE_EXHAUSTED", message: "You exceeded your current quota.")
        ])
        let client = GeminiAdAnalysisClient(gemini: .testing(transport))

        do {
            _ = try await client.analyze(Self.request())
            Issue.record("Expected a quota error")
        } catch let error as EpisodeAdAnalysisHTTPError {
            #expect(error.isCapExceeded)
        }
        #expect(transport.requests.count == 1)
    }

    @Test("Server errors retry and then succeed")
    func serverErrorsRetry() async throws {
        let transport = GeminiTestTransport([
            GeminiTestTransport.error(status: 503, statusText: "UNAVAILABLE", message: "overloaded"),
            .init(status: 200, body: try Self.answerBody([shortSpan(306)]))
        ])
        let client = GeminiAdAnalysisClient(gemini: .testing(transport))

        guard case .completed = try await client.analyze(Self.request()) else {
            Issue.record("Expected a completed response")
            return
        }
        #expect(transport.requests.count == 2)
    }

    @Test("A missing key fails before any request and gates the store unless Apple runs first")
    @MainActor
    func missingKeyGatesStore() async {
        let transport = GeminiTestTransport([])
        let client = GeminiAdAnalysisClient(gemini: .testing(transport, apiKey: "  "))

        await #expect(throws: EpisodeAdAnalysisError.apiKeyMissing) {
            _ = try await client.analyze(Self.request())
        }
        #expect(transport.requests.isEmpty)
        // Without a key the store is gated unless Apple's model runs first.
        let store = EpisodeAdAnalysisStore(configuration: GeminiConfiguration(apiKey: ""), transport: transport)
        #expect(store.canStartAnalysis == AppleFirstAdAnalysisClient.usesAppleForProcess)
    }

    @Test("Polling reports the job gone so the store resubmits locally")
    func pollReportsJobNotFound() async {
        let client = GeminiAdAnalysisClient(gemini: .testing(GeminiTestTransport([])))
        do {
            _ = try await client.pollJob(id: "anything")
            Issue.record("Expected job_not_found")
        } catch let error as EpisodeAdAnalysisHTTPError {
            #expect(error.isTransientJobFailure)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    // MARK: Fixtures

    static func request() -> EpisodeAdAnalysisAPIRequest {
        let segments: [(Int, TimeInterval, TimeInterval, String)] = [
            (106, 0, 600, "We discussed the history of paper advertisements."),
            (306, 600, 606.8, "Listen to Harbor Stories wherever you get podcasts."),
            (398, 606.8, 620, "Meet the people who make the harbor their home. Subscribe today."),
            (399, 620, 1_200, "Now returning to the history of boat construction."),
            (646, 1_200, 1_206.8, "Listen to Harbor Stories wherever you get podcasts."),
            (739, 1_206.8, 1_500, "That concludes our boatbuilding lesson, goodbye.")
        ]
        return EpisodeAdAnalysisAPIRequest(
            schemaVersion: 1,
            requestID: "test",
            episodeID: "episode",
            podcastID: "show",
            episodeTitle: nil,
            podcastTitle: nil,
            transcript: EpisodeAdAnalysisAPITranscriptMetadata(
                languageCode: "en",
                audioDuration: 1_500,
                fingerprint: "test",
                updatedAt: Date(timeIntervalSince1970: 0),
                state: "completed",
                segmentCount: segments.count
            ),
            segments: segments.map { EpisodeAdAnalysisAPISegment(id: $0.0, start: $0.1, end: $0.2, text: $0.3) }
        )
    }

    private func shortSpan(_ id: Int) -> AdAnalysisV3Output.Span {
        AdAnalysisV3Output.Span(
            kind: "house_or_network_promo",
            label: "Harbor Stories trailer",
            startSegmentID: id,
            endSegmentID: id,
            confidence: 0.95,
            evidenceQuote: "Listen to Harbor Stories",
            startQuote: "Listen to Harbor Stories",
            endQuote: "wherever you get podcasts"
        )
    }

    private func output(_ spans: [AdAnalysisV3Output.Span]) -> AdAnalysisV3Output {
        AdAnalysisV3Output(spans: spans)
    }

    private static func answerBody(_ spans: [AdAnalysisV3Output.Span]) throws -> Data {
        let answer = String(decoding: try JSONEncoder().encode(AdAnalysisV3Output(spans: spans)), as: UTF8.self)
        return GeminiTestTransport.answer(answer).body
    }
}
