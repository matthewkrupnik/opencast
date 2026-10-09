import Testing
@testable import OpenCast

@MainActor
@Suite("Auto-download policy")
struct AutoDownloadPolicyTests {
    @Test("A show's newest episode downloads once, only when opted in, unplayed, and not already downloaded")
    func decisionTable() {
        let cases: [(String?, Bool, Bool, AutoDownloadPolicy.Decision)] = [
            // Opted in and never checked, or a newer episode than the last handled one.
            ("", false, false, .download),
            ("older", false, false, .download),
            // Auto-download off never acts.
            (nil, false, false, .none),
            (nil, true, true, .none),
            // Already handled: a deleted or swept download is never fetched again.
            ("latest", false, false, .none),
            ("latest", true, true, .none),
            // Played, or a download record the user already owns: move past it.
            ("older", true, false, .markHandled),
            ("older", false, true, .markHandled),
            ("", true, true, .markHandled)
        ]

        for (handledEpisodeID, isPlayed, hasDownloadRecord, expected) in cases {
            let policy = AutoDownloadPolicy(
                latestEpisodeID: "latest",
                handledEpisodeID: handledEpisodeID,
                isPlayed: isPlayed,
                hasDownloadRecord: hasDownloadRecord
            )
            #expect(
                policy.decision == expected,
                "handled \(String(describing: handledEpisodeID)) played \(isPlayed) record \(hasDownloadRecord)"
            )
        }
    }
}
