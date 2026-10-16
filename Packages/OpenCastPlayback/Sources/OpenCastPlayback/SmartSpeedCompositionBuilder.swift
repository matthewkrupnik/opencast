import AVFoundation

/// Builds an AVPlayer-playable asset with long pauses removed, so Smart Speed
/// saves time by dropping silence rather than by changing playback rate.
nonisolated enum SmartSpeedCompositionBuilder {
    struct Result: @unchecked Sendable {
        let composition: AVMutableComposition
        let track: AVMutableCompositionTrack
        let timeline: SmartSpeedTimeline

        /// Mix parameters bound to the composition's track, so Voice Boost's
        /// tap attaches without waiting for a track load.
        func makeInputParameters() -> AVMutableAudioMixInputParameters {
            AVMutableAudioMixInputParameters(track: track)
        }
    }

    enum BuildError: Error {
        case noAudioTrack
    }

    @concurrent
    static func build(url: URL, analysis: SmartSpeedAnalysis) async throws -> Result {
        let timeline = SmartSpeedTimeline(silences: analysis.silenceRanges, originalDuration: analysis.duration)
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        return try await build(asset: asset, timeline: timeline)
    }

    @concurrent
    static func build(
        asset: AVURLAsset,
        timeline: SmartSpeedTimeline
    ) async throws -> Result {
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw BuildError.noAudioTrack
        }
        let timescale = try await sourceTrack.load(.naturalTimeScale)

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw BuildError.noAudioTrack
        }

        func time(_ seconds: TimeInterval) -> CMTime {
            CMTime(seconds: seconds, preferredTimescale: timescale)
        }

        // Append at the running end of the track so per-segment rounding can
        // never leave a gap or overlap between segments.
        var cursor = CMTime.zero
        for segment in timeline.segments {
            try Task.checkCancellation()
            let range = CMTimeRange(start: time(segment.originalStart), duration: time(segment.duration))
            try track.insertTimeRange(range, of: sourceTrack, at: cursor)
            cursor = cursor + range.duration
        }

        return Result(
            composition: composition,
            track: track,
            timeline: timeline
        )
    }
}
