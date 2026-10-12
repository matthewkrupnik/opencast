import Foundation
import OpenCastCore

/// A newly published episode worth announcing.
nonisolated struct NewEpisodeCandidate: Equatable, Sendable {
    var episodeID: String
    var feedURL: String
    var podcastTitle: String
    var title: String
    var summary: String?
    var publishedAt: Date
    var duration: TimeInterval?
    var episodeArtworkURL: URL?
    var podcastArtworkURL: URL?
}

/// Which episodes in a refreshed feed are genuinely new, mirroring the
/// notification server's rules: the first fetch of a feed is a silent
/// baseline, back-catalogue items never qualify, future-dated items wait,
/// and nothing older than 72 hours is announced.
nonisolated enum NewEpisodeDetector {
    static let recentWindow: TimeInterval = 72 * 60 * 60
    static let futureTolerance: TimeInterval = 5 * 60

    static func detect(
        preexisting: [EpisodeListItemSnapshot],
        snapshot: FeedSnapshot,
        now: Date
    ) -> [NewEpisodeCandidate] {
        guard !snapshot.isSalvaged, !preexisting.isEmpty else {
            return []
        }
        let knownIDs = Set(preexisting.map(\.episodeID))
        // Identity reconciliation can re-key old episodes; only items newer
        // than everything already cached can be new.
        let newestKnown = preexisting.compactMap(\.publishedAt).max() ?? .distantPast
        return snapshot.episodes.compactMap { episode in
            guard !knownIDs.contains(episode.id.rawValue),
                  let publishedAt = episode.publishedAt,
                  publishedAt > newestKnown,
                  publishedAt <= now.addingTimeInterval(futureTolerance),
                  now.timeIntervalSince(publishedAt) <= recentWindow
            else {
                return nil
            }
            return NewEpisodeCandidate(
                episodeID: episode.id.rawValue,
                feedURL: snapshot.podcast.id.rawValue,
                podcastTitle: snapshot.podcast.title,
                title: episode.title,
                summary: episode.summary,
                publishedAt: publishedAt,
                duration: episode.duration,
                episodeArtworkURL: episode.artworkURL,
                podcastArtworkURL: snapshot.podcast.artworkURL
            )
        }
    }
}
