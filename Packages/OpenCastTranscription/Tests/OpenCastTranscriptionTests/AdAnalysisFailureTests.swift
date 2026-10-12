import Foundation
import Testing
@testable import OpenCastTranscription

struct AdAnalysisFailureTests {
    @Test func typedFailureEnvelopeRemainsReadable() throws {
        let failure = OpenCastAdAnalysisFailure(category: .validationExhausted, retryDisposition: .explicitRetry, policyRevision: "revision-a")
        #expect(try JSONDecoder().decode(OpenCastAdAnalysisFailure.self, from: JSONEncoder().encode(failure)) == failure)
        #expect(failure.suppressesAutomaticReplay)
        #expect(!OpenCastAdAnalysisFailure(category: .capacity, retryDisposition: .afterCapacity).suppressesAutomaticReplay)
    }
}
