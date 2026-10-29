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

    @Test("A build without the entitlement never opens an Apple session")
    func notEntitledSkipsAppleSession() async throws {
        let (client, scripted, _) = makeClient(turns: [], apiKey: "")
        scripted.modelAvailability = .notEntitled

        do {
            _ = try await client.analyze(GeminiAdAnalysisClientTests.request())
            Issue.record("Expected an unavailable error")
        } catch let error as EpisodeAdAnalysisHTTPError {
            #expect(error.code == "apple_intelligence_unavailable")
            #expect(error.errorDescription == "Apple Intelligence isn’t available in this build.")
        }
        #expect(scripted.sessions.isEmpty)
    }

    @Test("Detect Ads stays available without a Gemini key while Apple can run")
    func storeAvailabilityFollowsEngines() {
        let noKey = GeminiConfiguration(apiKey: "")
        #expect(AppleFirstAdAnalysisClient.unavailableMessage(configuration: noKey, usesApple: true) == nil)
        #expect(AppleFirstAdAnalysisClient.unavailableMessage(configuration: noKey, usesApple: false) == GeminiConfiguration.missingKeyMessage)
    }

    @Test("An Apple call cut off by a crash skips Apple next launch and falls back to Gemini")
    func crashMidCallFallsBackToGemini() async throws {
        let defaults = try Self.defaults()
        AppleAdAnalysisCrashBreaker(defaults: defaults, processID: "crashed").begin()
        let (client, scripted, transport) = makeClient(
            turns: [.json(try Self.answer([Self.span(306)]))],
            geminiReplies: [.init(status: 200, body: try Self.geminiAnswer([Self.span(306)]))],
            defaults: defaults
        )

        guard case .completed(let response) = try await client.analyze(GeminiAdAnalysisClientTests.request()) else {
            Issue.record("Expected a completed response")
            return
        }
        #expect(response.model == AdAnalysisV3Payload.model)
        #expect(scripted.sessions.isEmpty)
        #expect(transport.requests.count == 1)
    }

    @Test("An Apple call cut off by a crash without a Gemini key reports Apple unavailable")
    func crashMidCallWithoutGemini() async throws {
        let defaults = try Self.defaults()
        AppleAdAnalysisCrashBreaker(defaults: defaults, processID: "crashed").begin()
        let (client, scripted, _) = makeClient(turns: [], apiKey: "", defaults: defaults)

        do {
            _ = try await client.analyze(GeminiAdAnalysisClientTests.request())
            Issue.record("Expected an unavailable error")
        } catch let error as EpisodeAdAnalysisHTTPError {
            #expect(error.code == "apple_intelligence_unavailable")
            #expect(error.statusCode == 503)
        }
        #expect(scripted.sessions.isEmpty)
    }

    @Test("A finished Apple call leaves no crash marker")
    func finishedCallClearsMarker() async throws {
        let defaults = try Self.defaults()
        let (client, _, _) = makeClient(turns: [.json(try Self.answer([Self.span(306)]))], defaults: defaults)

        _ = try await client.analyze(GeminiAdAnalysisClientTests.request())

        #expect(AppleAdAnalysisCrashBreaker(defaults: defaults, processID: "next-launch").suspension() == nil)
    }

    @Test("Apple is tried again once the crash cooldown passes")
    func cooldownExpires() throws {
        let defaults = try Self.defaults()
        let start = Date(timeIntervalSince1970: 1_000_000)
        AppleAdAnalysisCrashBreaker(defaults: defaults, processID: "crashed").begin()

        let launch = AppleAdAnalysisCrashBreaker(defaults: defaults, processID: "next", now: { start })
        #expect(launch.suspension() == start.addingTimeInterval(AppleAdAnalysisCrashBreaker.cooldown))
        let later = AppleAdAnalysisCrashBreaker(
            defaults: defaults,
            processID: "later",
            now: { start.addingTimeInterval(AppleAdAnalysisCrashBreaker.cooldown + 1) }
        )
        #expect(later.suspension() == nil)
    }

    // MARK: Fixtures

    private static func defaults() throws -> UserDefaults {
        let suiteName = "AppleFirstAdAnalysisClientTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeClient(
        turns: [ScriptedTranscriptIntelligenceClient.Turn],
        apiKey: String = "test-key",
        geminiReplies: [GeminiTestTransport.Reply] = [],
        defaults: UserDefaults? = nil
    ) -> (AppleFirstAdAnalysisClient, ScriptedTranscriptIntelligenceClient, GeminiTestTransport) {
        let scripted = ScriptedTranscriptIntelligenceClient()
        scripted.turns = turns
        nonisolated(unsafe) let shared = scripted
        let transport = GeminiTestTransport(geminiReplies)
        let client = AppleFirstAdAnalysisClient(
            apple: PrivateCloudComputeAdAnalysisClient(
                makeModelClient: { shared },
                crashBreaker: AppleAdAnalysisCrashBreaker(
                    defaults: defaults ?? UserDefaults(suiteName: "AppleFirstAdAnalysisClientTests.\(UUID().uuidString)")!
                )
            ),
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
