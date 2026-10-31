import FoundationModels
import Testing
@testable import OpenCast

@Suite("Private Cloud Compute entitlement")
struct PrivateCloudComputeEntitlementTests {
    @Test("This build is unentitled, so the features are off")
    func buildIsUnentitled() {
        #expect(!PrivateCloudComputeTranscriptIntelligenceClient.isEntitled)
        #expect(!TranscriptIntelligenceFeatureFlags.isEnabled)
    }

    @Test("An unentitled session fails before reaching Apple's model")
    func unentitledSessionNeverCallsModel() async {
        let session = PrivateCloudComputeTranscriptIntelligenceSession(
            session: LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: "Unused."),
            isEntitled: false
        )
        let options = TranscriptIntelligenceGenerationOptions(toolCalling: .disallowed)
        await #expect(throws: TranscriptIntelligenceFailure.notEntitled) {
            _ = try await session.respond(to: "Hi", options: options)
        }
    }
}
