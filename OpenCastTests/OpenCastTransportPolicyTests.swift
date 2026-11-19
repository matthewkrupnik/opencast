import Foundation
import Testing

@Suite("OpenCast transport policy")
struct OpenCastTransportPolicyTests {
    @Test("Allows user-provided HTTP podcast URLs")
    func allowsUserProvidedHTTPPodcastURLs() throws {
        let transportSecurity = try #require(
            Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
        )

        #expect(transportSecurity["NSAllowsArbitraryLoads"] as? Bool == true)
    }

    @Test("Permits only the static task identifiers, with processing for the charging catch-up")
    func permitsAdFreeContinuedProcessingTaskIdentifier() throws {
        let permittedIdentifiers = try #require(
            Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        )
        let backgroundModes = try #require(
            Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        )

        #expect(permittedIdentifiers == [
            "mk.lan.opencast.ad-free-pass",
            "mk.lan.opencast.transcript-generation",
            "mk.lan.opencast.chapters-summary",
            "mk.lan.opencast.charging-catch-up",
        ])
        // The overnight charging catch-up is a BGProcessingTask.
        #expect(backgroundModes.contains("processing"))
    }
}
