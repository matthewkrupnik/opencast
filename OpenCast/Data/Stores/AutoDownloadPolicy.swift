/// What Auto-Download does with a show's newest released episode. Only one
/// episode per show is ever considered, and each is decided once: the
/// handled ID moves past it whether it downloads or not, so a deleted or
/// played download is never fetched again. Pure so the table is
/// unit-testable.
struct AutoDownloadPolicy {
    enum Decision: Equatable {
        case none
        case markHandled
        case download
    }

    let latestEpisodeID: String
    /// Nil when the show has Auto-Download off.
    let handledEpisodeID: String?
    let isPlayed: Bool
    let hasDownloadRecord: Bool

    var decision: Decision {
        guard let handledEpisodeID, handledEpisodeID != latestEpisodeID else {
            return .none
        }
        // Already played, or a download the user started, paused, deleted
        // into `.missing`, or that failed: theirs to manage, not ours.
        if isPlayed || hasDownloadRecord {
            return .markHandled
        }
        return .download
    }
}
