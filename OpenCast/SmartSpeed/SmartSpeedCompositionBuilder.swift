import AVFoundation

/// Builds an AVPlayer-playable asset with long pauses removed, so Smart Speed
/// saves time by dropping silence rather than by changing playback rate.
nonisolated enum SmartSpeedCompositionBuilder {
    struct Result: @unchecked Sendable {
        let composition: AVMutableComposition
        /// Short fades either side of each cut. Voice Boost's tap must be added
        /// to these same input parameters, since an item has one audio mix.
        let audioMix: AVMutableAudioMix
    }

    enum BuildError: Error {
        case noAudioTrack
    }

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
            let range = CMTimeRange(start: time(segment.originalStart), duration: time(segment.duration))
            try track.insertTimeRange(range, of: sourceTrack, at: cursor)
            cursor = cursor + range.duration
        }

        let parameters = AVMutableAudioMixInputParameters(track: track)
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
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [parameters]

        return Result(composition: composition, audioMix: audioMix)
    }
}
