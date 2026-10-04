import AVFoundation

struct SilenceRegion: Sendable {
    let startFrame: AVAudioFramePosition
    let endFrame: AVAudioFramePosition
}

final class SilenceDetector: @unchecked Sendable {
    private let thresholdLinear: Float
    private let minimumSilenceFrames: Int
    private let attackFrames: Int
    private let releaseFrames: Int
    private let windowSize = 512

    init(settings: SmartSpeedSettings, sampleRate: Double) {
        thresholdLinear = Float(pow(10.0, settings.silenceThresholdDBFS / 20.0))
        minimumSilenceFrames = Int(settings.minimumSilenceDuration * sampleRate)
        attackFrames = Int(settings.attackDuration * sampleRate)
        releaseFrames = Int(settings.releaseDuration * sampleRate)
    }

    /// Scan buffer and emit silence regions in absolute file-frame coordinates.
    func detect(in buffer: AVAudioPCMBuffer, frameOffset: AVAudioFramePosition) -> [SilenceRegion] {
        guard let data = buffer.floatChannelData else { return [] }
        let length = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        var rms = [Float](repeating: 0, count: max(length / 64, 1))
        var rmsCount = 0

        // Windowed RMS (hop 64)
        var i = 0
        while i < length {
            var sumSq: Float = 0
            let n = min(windowSize, length - i)
            for ch in 0..<channels {
                let p = data[ch]
                for j in 0..<n { sumSq += p[i + j] * p[i + j] }
            }
            rms[rmsCount] = sqrt(sumSq / Float(n * channels))
            rmsCount += 1
            i += 64
        }

        var regions: [SilenceRegion] = []
        var silentRun = 0
        var inSilence = false
        var silenceStart = 0

        for idx in 0..<rmsCount {
            let isSilent = rms[idx] < thresholdLinear
            if isSilent {
                if !inSilence {
                    silentRun = 0
                    silenceStart = idx * 64
                    inSilence = true
                }
                silentRun += 64
            } else {
                if inSilence && silentRun >= minimumSilenceFrames {
                    regions.append(SilenceRegion(
                        startFrame: frameOffset + Int64(silenceStart),
                        endFrame: frameOffset + Int64(silenceStart + silentRun)))
                }
                inSilence = false
                silentRun = 0
            }
        }
        
        if inSilence && silentRun >= minimumSilenceFrames {
            regions.append(SilenceRegion(
                startFrame: frameOffset + Int64(silenceStart),
                endFrame: frameOffset + Int64(silenceStart + silentRun)))
        }
        
        return regions
    }
}