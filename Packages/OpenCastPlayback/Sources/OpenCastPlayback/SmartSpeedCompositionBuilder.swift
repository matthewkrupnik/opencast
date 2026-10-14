import AVFoundation

/// Builds an AVPlayer-playable asset with long pauses removed, so Smart Speed
/// saves time by dropping silence rather than by changing playback rate.
nonisolated enum SmartSpeedCompositionBuilder {
    struct Result: @unchecked Sendable {
        let composition: AVMutableComposition
        let track: AVMutableCompositionTrack
        let timescale: CMTimeScale
        let timeline: SmartSpeedTimeline
        let fadeDuration: TimeInterval

        /// Short fades either side of each cut. Voice Boost's tap must be set
        /// on these same parameters, since an item has one audio mix.
        func makeInputParameters() -> AVMutableAudioMixInputParameters {
            let parameters = AVMutableAudioMixInputParameters(track: track)
            func time(_ seconds: TimeInterval) -> CMTime {
                CMTime(seconds: seconds, preferredTimescale: timescale)
            }
            for segment in timeline.segments.dropFirst() {
                let cut = segment.compositionStart
                parameters.setVolumeRamp(
                    fromStartVolume: 1,
                    toEndVolume: 0,
                    timeRange: CMTimeRange(start: time(cut - fadeDuration), duration: time(fadeDuration))
                )
                parameters.setVolumeRamp(
                    fromStartVolume: 0,
                    toEndVolume: 1,
                    timeRange: CMTimeRange(start: time(cut), duration: time(fadeDuration))
                )
            }
            return parameters
        }

        var audioMix: AVMutableAudioMix {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = [makeInputParameters()]
            return audioMix
        }
    }

    enum BuildError: Error {
        case noAudioTrack
    }

    /// Finds the pauses in a downloaded file and builds its shortened copy,
    /// off the main actor: analysis decodes the whole file.
    @concurrent
    static func make(url: URL) async throws -> Result {
        let analysis = try SmartSpeedAnalyzer.analyze(url: url)
        let timeline = SmartSpeedTimeline(silences: analysis.silenceRanges, originalDuration: analysis.duration)
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        return try await build(asset: asset, timeline: timeline)
    }

    @concurrent
    static func build(
        asset: AVURLAsset,
        timeline: SmartSpeedTimeline,
        fadeDuration: TimeInterval = 0.005
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
            timescale: timescale,
            timeline: timeline,
            fadeDuration: fadeDuration
        )
    }
}
