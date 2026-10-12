import Foundation
import SwiftData

/// Device-local persistence for pending ad-free pass queue items. Never
/// synced; registered only in the local SwiftData configuration.
@Model
final class AdFreePassQueueItemRecord {
    var episodeID: String = ""
    var podcastID: String = ""
    var originRawValue: String = ""
    var enqueuedAt: Date = Date()
    var sequence: Int = 0
    /// Unused since cloud detection was removed; kept so the local store
    /// schema stays stable.
    var modeRawValue: String = ""

    init(
        episodeID: String,
        podcastID: String,
        originRawValue: String,
        enqueuedAt: Date = .now,
        sequence: Int,
        modeRawValue: String = ""
    ) {
        self.episodeID = episodeID
        self.podcastID = podcastID
        self.originRawValue = originRawValue
        self.enqueuedAt = enqueuedAt
        self.sequence = sequence
        self.modeRawValue = modeRawValue
    }
}
