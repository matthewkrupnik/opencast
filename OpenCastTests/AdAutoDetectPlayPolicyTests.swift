import Testing
@testable import OpenCast

@MainActor
@Suite("Auto-detect play policy")
struct AdAutoDetectPlayPolicyTests {
    @Test("Play qualifies for an auto pass only when opted in, unanalyzed, and out of the queue")
    func playQualificationTable() {
        let cases: [(Bool, Bool, AdFreePassQueueEpisodeStatus, Bool)] = [
            // Qualifying: toggle on, no current analysis, not in the queue.
            (true, false, .notQueued, true),
            // A failed item left the queue — the next play retries it.
            (true, false, .failed(message: "probe"), true),
            // Toggle off never enqueues.
            (false, false, .notQueued, false),
            (false, false, .failed(message: "probe"), false),
            // A current completed analysis never re-analyzes.
            (true, true, .notQueued, false),
            (true, true, .failed(message: "probe"), false),
            // Already queued, running, or finished this session.
            (true, false, .queued(ahead: 1), false),
            (true, false, .queued(ahead: 0), false),
            (true, false, .running, false),
            (true, false, .completed(zoneCount: 2), false),
            // It needed the listener's key this session; playing it again
            // would only ask again.
            (true, false, .keyRequired(.noKey), false)
        ]

        for (isEnabled, hasAnalysis, status, expected) in cases {
            let policy = AdAutoDetectPlayPolicy(
                isAutoDetectEnabled: isEnabled,
                hasCurrentCompletedAnalysis: hasAnalysis,
                queueStatus: status
            )
            #expect(
                policy.shouldEnqueue == expected,
                "enabled \(isEnabled) hasAnalysis \(hasAnalysis) status \(status)"
            )
        }
    }

    @Test("A transcript stale for the current download re-qualifies, even after a pass completed this session")
    func staleTranscriptQualificationTable() {
        let cases: [(Bool, AdFreePassQueueEpisodeStatus, Bool)] = [
            // The old analysis looks current against its own transcript.
            (true, .notQueued, true),
            (true, .completed(zoneCount: 2), true),
            (false, .completed(zoneCount: 0), true),
            (true, .failed(message: "probe"), true),
            // Still never doubles up on queued or running work.
            (true, .queued(ahead: 0), false),
            (true, .running, false),
            (true, .keyRequired(.noKey), false)
        ]

        for (hasAnalysis, status, expected) in cases {
            let policy = AdAutoDetectPlayPolicy(
                isAutoDetectEnabled: true,
                hasCurrentCompletedAnalysis: hasAnalysis,
                queueStatus: status,
                isTranscriptStaleForDownload: true
            )
            #expect(policy.shouldEnqueue == expected, "hasAnalysis \(hasAnalysis) status \(status)")
        }

        let disabled = AdAutoDetectPlayPolicy(
            isAutoDetectEnabled: false,
            hasCurrentCompletedAnalysis: true,
            queueStatus: .notQueued,
            isTranscriptStaleForDownload: true
        )
        #expect(!disabled.shouldEnqueue)
    }
}
