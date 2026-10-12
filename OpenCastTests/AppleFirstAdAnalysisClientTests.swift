import Foundation
import Testing
@testable import OpenCast

/// Detect Ads on Apple's Private Cloud Compute with Gemini as the fallback,
/// scripted through the PCC test client and the Gemini test transport.
@MainActor
@Suite("Apple-first ad analysis")
struct AppleFirstAdAnalysisClientTests {
    @Test("A clean Apple answer completes without touching Gemini")
    func appleAnswerCompletes() async throws {
        let (client, scripted, transport) = makeClient(turns: [.json(try Self.answer([Self.span(306), Self.span(646)]))])

        guard case .completed(let response) = try await client.analyze(GeminiAdAnalysisClientTests.request()) else {
            Issue.record("Expected a completed response")
            return
        }
        #expect(response.model == PrivateCloudComputeAdAnalysisClient.model)
        #expect(response.policy == AdAnalysisV3Payload.policy)
        #expect(response.policyRevision == GeminiAdAnalysisClient.policyRevision)
        #expect(response.spans.map(\.startTime) == [600, 1_200])
        #expect(scripted.sessions.first?.instructions == AdAnalysisV3Payload.instructions)
        #expect(transport.requests.isEmpty)
    }

    @Test("An invalid Apple answer is repaired once in the same session")
    func invalidAnswerRepairedInSession() async throws {
        var bad = Self.span(306)
        bad.startSegmentID = 106
        let (client, scripted, transport) = makeClient(turns: [
            .json(try Self.answer([bad])),
            .json(try Self.answer([Self.span(306)])),
        ])

        guard case .completed(let response) = try await client.analyze(GeminiAdAnalysisClientTests.request()) else {
            Issue.record("Expected a completed response")
            return
        }
        #expect(response.warnings.contains("v3_semantic_repair"))
        #expect(scripted.sessions.count == 1)
        #expect(scripted.sessions.first?.prompts.count == 2)
        #expect(scripted.sessions.first?.prompts.last?.contains("v3_boundary_receipt_mismatch:106-306") == true)
        #expect(transport.requests.isEmpty)
    }

    @Test("A context overflow retries with smaller windows")
    func contextOverflowShrinksWindows() async throws {
        let (client, scripted, _) = makeClient(turns: [
            .failure(.contextSizeExceeded(tokenCount: 40_000, contextSize: 32_000)),
            .json(try Self.answer([Self.span(306)])),
        ])

        guard case .completed = try await client.analyze(GeminiAdAnalysisClientTests.request()) else {
            Issue.record("Expected a completed response")
            return
        }
        #expect(scripted.sessions.count == 2)
    }

    @Test("An Apple outage falls back to Gemini when a key is configured")
    func outageFallsBackToGemini() async throws {
        let (client, _, transport) = makeClient(
            turns: [.failure(.serviceUnavailable)],
            geminiReplies: [.init(status: 200, body: try Self.geminiAnswer([Self.span(306)]))]
        )

        guard case .completed(let response) = try await client.analyze(GeminiAdAnalysisClientTests.request()) else {
            Issue.record("Expected a completed response")
            return
        }
        #expect(response.model == AdAnalysisV3Payload.model)
        #expect(transport.requests.count == 1)
    }

    @Test("A reached Apple limit without a Gemini key defers like a cap")
    func quotaWithoutGeminiIsCapDeferral() async throws {
        let (client, scripted, transport) = makeClient(turns: [], apiKey: "")
        scripted.quota.isLimitReached = true

        do {
            _ = try await client.analyze(GeminiAdAnalysisClientTests.request())
            Issue.record("Expected a limit error")
        } catch let error as EpisodeAdAnalysisHTTPError {
            #expect(error.isCapExceeded)
            #expect(error.code == "apple_intelligence_limit_reached")
        }
        #expect(scripted.sessions.isEmpty)
        #expect(transport.requests.isEmpty)
    }

    @Test("Apple Intelligence off without a Gemini key says how to turn it on")
    func appleIntelligenceOffWithoutGemini() async throws {
        let (client, scripted, _) = makeClient(turns: [], apiKey: "")
        scripted.modelAvailability = .appleIntelligenceNotEnabled

        do {
            _ = try await client.analyze(GeminiAdAnalysisClientTests.request())
            Issue.record("Expected an unavailable error")
        } catch let error as EpisodeAdAnalysisHTTPError {
            #expect(error.code == "apple_intelligence_unavailable")
            #expect(error.errorDescription == "Turn on Apple Intelligence in Settings to detect ads.")
        }
    }

    @Test("Detect Ads stays available without a Gemini key while Apple can run")
    func storeAvailabilityFollowsEngines() {
        let noKey = GeminiConfiguration(apiKey: "")
        #expect(AppleFirstAdAnalysisClient.unavailableMessage(configuration: noKey, usesApple: true) == nil)
        #expect(AppleFirstAdAnalysisClient.unavailableMessage(configuration: noKey, usesApple: false) == GeminiConfiguration.missingKeyMessage)
    }

    // MARK: Fixtures

    private func makeClient(
        turns: [ScriptedTranscriptIntelligenceClient.Turn],
        apiKey: String = "test-key",
        geminiReplies: [GeminiTestTransport.Reply] = []
    ) -> (AppleFirstAdAnalysisClient, ScriptedTranscriptIntelligenceClient, GeminiTestTransport) {
        let scripted = ScriptedTranscriptIntelligenceClient()
        scripted.turns = turns
        nonisolated(unsafe) let shared = scripted
        let transport = GeminiTestTransport(geminiReplies)
        let client = AppleFirstAdAnalysisClient(
            apple: PrivateCloudComputeAdAnalysisClient(makeModelClient: { shared }),
            gemini: GeminiAdAnalysisClient(gemini: .testing(transport, apiKey: apiKey)),
            usesApple: true
        )
        return (client, scripted, transport)
    }

    private static func span(_ id: Int) -> AdAnalysisV3Output.Span {
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

    private static func answer(_ spans: [AdAnalysisV3Output.Span]) throws -> String {
        String(decoding: try JSONEncoder().encode(AdAnalysisV3Output(spans: spans)), as: UTF8.self)
    }

    private static func geminiAnswer(_ spans: [AdAnalysisV3Output.Span]) throws -> Data {
        GeminiTestTransport.answer(try answer(spans)).body
    }
}
