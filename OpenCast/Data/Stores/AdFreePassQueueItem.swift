import Foundation

struct AdFreePassQueueItem: Identifiable, Equatable {
    let episode: EpisodeListItemSnapshot
    let origin: AdFreePassQueueOrigin
    let enqueuedAt: Date
    let sequence: Int

    init(
        episode: EpisodeListItemSnapshot,
        origin: AdFreePassQueueOrigin,
        enqueuedAt: Date,
        sequence: Int
    ) {
        self.episode = episode
        self.origin = origin
        self.enqueuedAt = enqueuedAt
        self.sequence = sequence
    }

    var id: String {
        episode.episodeID
    }

    var episodeID: String {
        episode.episodeID
    }
}
