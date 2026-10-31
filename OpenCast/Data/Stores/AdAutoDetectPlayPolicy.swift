/// Decision-11 qualification for play-triggered auto ad detection: playing
/// an episode of an auto-detect-enabled show enqueues an `.auto` pass iff
/// the episode has no current completed analysis and is not already in the
/// queue. Pure so the table is unit-testable.
struct AdAutoDetectPlayPolicy {
    let isAutoDetectEnabled: Bool
    let hasCurrentCompletedAnalysis: Bool
    let queueStatus: AdFreePassQueueEpisodeStatus

    var isReplaySuppressed = false
    /// The completed transcript describes other audio than the current
    /// download (an enclosure re-downloaded with other ads stitched in), so
    /// its analysis is no use and a pass finished earlier this session
    /// doesn't count.
    var isTranscriptStaleForDownload = false

    var shouldEnqueue: Bool {
        guard isAutoDetectEnabled,
              isTranscriptStaleForDownload || !hasCurrentCompletedAnalysis,
              !isReplaySuppressed
        else {
            return false
        }

        switch queueStatus {
        case .notQueued, .failed:
            return true
        case .completed:
            return isTranscriptStaleForDownload
        case .queued, .running:
            return false
        case .keyRequired:
            // Playing it again would only ask for the same key again.
            return false
        }
    }
}
