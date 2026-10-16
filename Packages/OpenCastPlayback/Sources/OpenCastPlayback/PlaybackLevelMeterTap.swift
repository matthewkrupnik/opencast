@preconcurrency import AVFoundation
import Foundation
@preconcurrency import MediaToolbox
import Synchronization

/// Diagnostic level meter for the Smart Speed item. It reads the audio the
/// app hands to the system, after the cut fades, and never changes it, so a
/// heard volume drop can be pinned on the app or on the output route.
nonisolated final class PlaybackLevelMeterTap {
    struct Window: Sendable {
        let start: TimeInterval
        let end: TimeInterval
        let rmsDB: Double
        let peakDB: Double
    }

    let audioTapProcessor: MTAudioProcessingTap
    private let meter: PlaybackLevelMeter

    init?() {
        let meter = PlaybackLevelMeter()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(meter).toOpaque(),
            init: { _, clientInfo, storageOut in
                storageOut.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<PlaybackLevelMeter>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                PlaybackLevelMeter.from(tap).prepare(format: format.pointee)
            },
            unprepare: nil,
            process: { tap, numberFrames, _, bufferList, framesOut, flagsOut in
                var range = CMTimeRange()
                guard MTAudioProcessingTapGetSourceAudio(
                    tap, numberFrames, bufferList, flagsOut, &range, framesOut
                ) == noErr else {
                    framesOut.pointee = 0
                    return
                }
                PlaybackLevelMeter.from(tap).accumulate(bufferList, range: range)
            }
        )
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        ) == noErr, let tap else {
            Unmanaged.passUnretained(meter).release()
            return nil
        }
        audioTapProcessor = tap
        self.meter = meter
    }

    /// Completed windows since the last call, on the player's clock.
    func drainWindows() -> [Window] {
        meter.drainWindows()
    }
}

nonisolated private final class PlaybackLevelMeter: Sendable {
    private struct State {
        var isFloat = false
        var start = Double.nan
        var end = 0.0
        var sumSquares = 0.0
        var sampleCount = 0
        var peak: Float = 0
        var windows: [PlaybackLevelMeterTap.Window] = []
    }

    private static let windowSeconds = 5.0
    private static let maximumPendingWindows = 64
    private let state = Mutex(State())

    static func from(_ tap: MTAudioProcessingTap) -> PlaybackLevelMeter {
        Unmanaged<PlaybackLevelMeter>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    }

    func prepare(format: AudioStreamBasicDescription) {
        let isFloat = format.mFormatID == kAudioFormatLinearPCM
            && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
            && format.mBitsPerChannel == 32
        state.withLock { $0.isFloat = isFloat }
    }

    func accumulate(_ bufferList: UnsafeMutablePointer<AudioBufferList>, range: CMTimeRange) {
        let start = range.start.seconds
        let end = range.end.seconds
        guard start.isFinite, end.isFinite else {
            return
        }

        var sumSquares = 0.0
        var sampleCount = 0
        var peak: Float = 0
        for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                continue
            }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            for index in 0..<count {
                let sample = data[index]
                sumSquares += Double(sample * sample)
                peak = max(peak, abs(sample))
            }
            sampleCount += count
        }

        state.withLock { state in
            guard state.isFloat else {
                return
            }
            // A seek or item change jumps the clock; drop the partial window.
            if state.start.isNaN || abs(start - state.end) > 0.5 {
                state.start = start
                state.sumSquares = 0
                state.sampleCount = 0
                state.peak = 0
            }
            state.end = end
            state.sumSquares += sumSquares
            state.sampleCount += sampleCount
            state.peak = max(state.peak, peak)

            guard state.end - state.start >= Self.windowSeconds, state.sampleCount > 0 else {
                return
            }
            let rms = (state.sumSquares / Double(state.sampleCount)).squareRoot()
            state.windows.append(PlaybackLevelMeterTap.Window(
                start: state.start,
                end: state.end,
                rmsDB: 20 * log10(max(rms, 1e-9)),
                peakDB: 20 * log10(max(Double(state.peak), 1e-9))
            ))
            if state.windows.count > Self.maximumPendingWindows {
                state.windows.removeFirst(state.windows.count - Self.maximumPendingWindows)
            }
            state.start = state.end
            state.sumSquares = 0
            state.sampleCount = 0
            state.peak = 0
        }
    }

    func drainWindows() -> [PlaybackLevelMeterTap.Window] {
        state.withLock { state in
            defer { state.windows = [] }
            return state.windows
        }
    }
}
