import Foundation
import OpenCastCore

public struct PlaybackSnapshot: Equatable, Sendable {
    public var state: PlaybackState
    public var currentEpisode: Episode?
    public var position: TimeInterval
    public var duration: TimeInterval?
    public var rate: Float
    public var sleepTimerEndsAt: Date?
    public var progressBoundaryID: Int
    public var skipZones: [PlaybackSkipZone]
    /// The playing chapter's art, shown in place of the episode artwork.
    public var chapterArtworkURL: URL?

    public init(
        state: PlaybackState = .idle,
        currentEpisode: Episode? = nil,
        position: TimeInterval = 0,
        duration: TimeInterval? = nil,
        rate: Float = 1,
        sleepTimerEndsAt: Date? = nil,
        progressBoundaryID: Int = 0,
        skipZones: [PlaybackSkipZone] = [],
        chapterArtworkURL: URL? = nil
    ) {
        self.state = state
        self.currentEpisode = currentEpisode
        self.position = position
        self.duration = duration
        self.rate = rate
        self.sleepTimerEndsAt = sleepTimerEndsAt
        self.progressBoundaryID = progressBoundaryID
        self.skipZones = skipZones
        self.chapterArtworkURL = chapterArtworkURL
    }

    /// What system Now Playing surfaces show: chapter art over episode art.
    public nonisolated var displayArtworkURL: URL? {
        chapterArtworkURL ?? currentEpisode?.artworkURL
    }

    public nonisolated var normalizedProgress: Double {
        normalizedProgress(for: position)
    }

    public nonisolated func normalizedProgress(for position: TimeInterval) -> Double {
        guard let duration, duration.isFinite, duration > 0, position.isFinite else {
            return 0
        }

        return (position / duration).clamped01
    }
}
