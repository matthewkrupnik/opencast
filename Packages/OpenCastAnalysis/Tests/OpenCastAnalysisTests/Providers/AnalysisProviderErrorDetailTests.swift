import Foundation
@testable import OpenCastAnalysis
@testable import OpenCastAnalysisProviders
import Testing

@Suite("Provider error detail")
struct AnalysisProviderErrorDetailTests {
    let verifier = SecretVerifier(secrets: [ProviderTestKeys.googleText])

    @Test("A Gemini 400 keeps its status, known reasons and one-line message on the send, and logs no message")
    func geminiRejection() async throws {
        let body = #"{"error":{"code":400,"message":"The input token count (1200000) exceeds\nthe maximum number of tokens allowed (1048576).","status":"INVALID_ARGUMENT","details":[{"reason":"SERVICE_DISABLED"},{"reason":"SOMETHING_NEW"}]}}"#
        let log = AnalysisProviderSendLog()
        let sink = CollectingLogSink()
        let transport = try ProviderTestSupport.googleTransport(ScriptedHTTPClient(status: 400, body: body), observer: log, sink: sink)
        _ = await ProviderTestSupport.sendResult(transport, try ProviderTestSupport.adWindowRequest(model: ProviderTestSupport.googleEntry()))

        let send = try #require(log.sends.first)
        #expect(send.status == 400)
        #expect(send.failure == .requestRejected)
        #expect(send.providerError == AnalysisProviderErrorDetail(
            errorStatus: "INVALID_ARGUMENT",
            reasons: ["SERVICE_DISABLED", "unknown"],
            message: "The input token count (1200000) exceeds the maximum number of tokens allowed (1048576)."
        ))
        let line = try #require(sink.all.first { $0.contains("outcome=failed") })
        #expect(line.contains("error_status=INVALID_ARGUMENT reasons=SERVICE_DISABLED:unknown"))
        #expect(!line.contains("token count"))
    }

    @Test("An unknown status reads as unknown; a body with no error object gives no detail")
    func unknownAndMissing() {
        let unknown = AnalysisProviderErrorDetail.read(#"{"error":{"status":"BRAND_NEW"}}"#, provider: .google, verifier: verifier)
        #expect(unknown == .init(errorStatus: "unknown", reasons: [], message: nil))
        #expect(AnalysisProviderErrorDetail.read("<html>Bad Gateway</html>", provider: .google, verifier: verifier) == nil)
        #expect(AnalysisProviderErrorDetail.read(#"{"other":1}"#, provider: .google, verifier: verifier) == nil)
    }

    @Test("OpenAI keeps its type, code and param")
    func openAI() {
        let body = #"{"error":{"message":"bad","type":"invalid_request_error","code":"context_length_exceeded","param":"input"}}"#
        let detail = AnalysisProviderErrorDetail.read(body, provider: .openai, verifier: verifier)
        #expect(detail == .init(errorStatus: "invalid_request_error", reasons: ["context_length_exceeded", "param.input"], message: "bad"))
    }

    @Test("A message holding the key or a key shape is dropped; a long one is capped")
    func messageChecks() {
        #expect(AnalysisProviderErrorDetail.message("Key \(ProviderTestKeys.googleText) is bad", verifier: verifier) == nil)
        let other = "AIza" + "Sy" + String(repeating: "Zq4", count: 11) + "w1"
        #expect(AnalysisProviderErrorDetail.message("Key \(other) is bad", verifier: verifier) == nil)
        #expect(AnalysisProviderErrorDetail.message("  \n ", verifier: verifier) == nil)
        let long = AnalysisProviderErrorDetail.message(String(repeating: "word ", count: 200), verifier: verifier)
        #expect(long?.count == AnalysisProviderErrorDetail.maximumMessageLength)
        #expect(long?.hasSuffix("…") == true)
    }
}
