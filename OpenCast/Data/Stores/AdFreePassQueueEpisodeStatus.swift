enum AdFreePassQueueEpisodeStatus: Equatable {
    case notQueued
    case queued(ahead: Int)
    case running
    case completed(zoneCount: Int)
    case failed(message: String)
    /// Ad detection needed the listener's own key; the surfaces say how to
    /// add one.
    case keyRequired(AnalysisKeyRequiredReason)
}
