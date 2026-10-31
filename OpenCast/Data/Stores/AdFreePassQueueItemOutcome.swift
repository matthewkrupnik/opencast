struct AdFreePassQueueItemOutcome: Identifiable, Equatable {
    enum Kind: Equatable {
        case completed(zoneCount: Int)
        case failed(message: String)
        /// Ad detection needed the listener's own key (no key, the trial
        /// used or paused, its service unreachable, the Keychain locked).
        /// The episode's analysis record keeps the reason across launches.
        case keyRequired(AnalysisKeyRequiredReason)
    }

    let episodeID: String
    let episodeTitle: String
    let artworkURL: String?
    let kind: Kind

    var id: String {
        episodeID
    }
}
