import Accelerate
import AVFoundation

nonisolated struct SilenceRegion: Sendable {
    let startFrame: AVAudioFramePosition
    let endFrame: AVAudioFramePosition
}

nonisolated final class SilenceDetector: @unchecked Sendable {
    private let thresholdLinear: Float
    private let minimumSilenceFrames: Int
    private let windowSize = 512
    private let hopSize = 64

    init(
        sampleRate: Double,
        thresholdDBFS: Double = -45,
        minimumSilenceDuration: TimeInterval = 0.25
    ) {
        thresholdLinear = Float(pow(10.0, thresholdDBFS / 20.0))
        minimumSilenceFrames = Int(minimumSilenceDuration * sampleRate)
    }

    // Silence still open at the end of the previous buffer, so pauses that
    // straddle a chunk boundary are reported once, at full length.
    private var openSilenceStart: AVAudioFramePosition?
    private var openSilenceEnd: AVAudioFramePosition = 0

    /// Scan buffer and emit silence regions in absolute file-frame coordinates.
    /// Buffers must be fed in file order; call `finish()` after the last one.
    func detect(in buffer: AVAudioPCMBuffer, frameOffset: AVAudioFramePosition) -> [SilenceRegion] {
        guard let data = buffer.floatChannelData else { return [] }
        let length = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        var regions: [SilenceRegion] = []

        // Energy per 64-frame hop, computed once; each 512-frame window is the
        // sum of the hops it covers.
        let hopCount = (length + hopSize - 1) / hopSize
        var hopEnergy = [Float](repeating: 0, count: hopCount)
        for h in 0..<hopCount {
            let n = vDSP_Length(min(hopSize, length - h * hopSize))
            for ch in 0..<channels {
                var sumSq: Float = 0
                vDSP_svesq(data[ch] + h * hopSize, 1, &sumSq, n)
                hopEnergy[h] += sumSq
            }
        }

        // Windowed RMS (hop 64)
        let hopsPerWindow = windowSize / hopSize
        var windowEnergy = hopEnergy.prefix(hopsPerWindow).reduce(0, +)
        for h in 0..<hopCount {
            let i = h * hopSize
            let n = min(windowSize, length - i)
            let rms = sqrt(max(windowEnergy, 0) / Float(n * channels))
            let hopStart = frameOffset + AVAudioFramePosition(i)
            let hopEnd = frameOffset + AVAudioFramePosition(min(i + hopSize, length))
            windowEnergy -= hopEnergy[h]
            if h + hopsPerWindow < hopCount {
                windowEnergy += hopEnergy[h + hopsPerWindow]
            }

            if rms < thresholdLinear {
                if openSilenceStart == nil {
                    openSilenceStart = hopStart
                }
                openSilenceEnd = hopEnd
            } else if let region = closeOpenSilence() {
                regions.append(region)
            }
        }

        return regions
    }

    /// Emits the silence still open at end of file, if long enough.
    func finish() -> [SilenceRegion] {
        closeOpenSilence().map { [$0] } ?? []
    }

    private func closeOpenSilence() -> SilenceRegion? {
        guard let start = openSilenceStart else { return nil }
        openSilenceStart = nil
        guard openSilenceEnd - start >= AVAudioFramePosition(minimumSilenceFrames) else { return nil }
        return SilenceRegion(startFrame: start, endFrame: openSilenceEnd)
    }
}
