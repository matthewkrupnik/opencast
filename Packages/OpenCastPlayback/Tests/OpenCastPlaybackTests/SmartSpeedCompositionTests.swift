import AVFoundation
import Foundation
import Testing
@testable import OpenCastPlayback

@MainActor
@Suite("Smart Speed composition")
struct SmartSpeedCompositionTests {
    @Test("Long pauses are trimmed to the kept pause and short ones are left alone")
    func timelineTrimsLongPauses() {
        let timeline = SmartSpeedTimeline(
            silences: [1.0...2.0, 3.0...3.2, 5.0...5.5],
            originalDuration: 8,
            keptPause: 0.2,
            minimumPause: 0.3
        )

        #expect(timeline.segments.count == 3)
        #expect(abs(timeline.timeSaved - (0.8 + 0.3)) < 1e-9)
        #expect(abs(timeline.compositionDuration - (8 - 1.1)) < 1e-9)
        // Half the kept pause stays on each side of the cut.
        #expect(abs(timeline.segments[0].originalEnd - 1.1) < 1e-9)
        #expect(abs(timeline.segments[1].originalStart - 1.9) < 1e-9)
    }

    @Test("Times round-trip between the original and shortened clocks")
    func timelineMapsBothWays() {
        let timeline = SmartSpeedTimeline(silences: [1.0...2.0], originalDuration: 4)

        // Before the cut, the clocks agree.
        #expect(abs(timeline.compositionTime(forOriginal: 0.5) - 0.5) < 1e-9)
        // After the cut, the shortened clock is 0.8s behind.
        #expect(abs(timeline.compositionTime(forOriginal: 3.0) - 2.2) < 1e-9)
        #expect(abs(timeline.originalTime(forComposition: 2.2) - 3.0) < 1e-9)
        // Inside the removed span, positions collapse onto the cut point.
        #expect(abs(timeline.compositionTime(forOriginal: 1.5) - 1.1) < 1e-9)
        #expect(abs(timeline.originalTime(forComposition: 1.1) - 1.9) < 1e-9)

        for original in stride(from: 0.0, through: 4.0, by: 0.05) where !(1.1..<1.9).contains(original) {
            let roundTrip = timeline.originalTime(forComposition: timeline.compositionTime(forOriginal: original))
            #expect(abs(roundTrip - original) < 1e-9)
        }
    }

    @Test("The analyzer finds pauses in 44.1 kHz audio, including one across a chunk boundary")
    func analyzerFindsPauses() throws {
        let url = try SmartSpeedAudioFixture.write(pattern: Self.shortPattern)
        defer { try? FileManager.default.removeItem(at: url) }

        let analysis = try SmartSpeedAnalyzer.analyze(url: url)
        let found = analysis.silenceRanges

        #expect(analysis.sampleRate == 44_100)
        // The 0.15s pause is below the 0.25s minimum and is not reported.
        try #require(found.count == 2, "found \(found)")
        // 0.8–1.3 straddles the 1s analysis chunk and must not be split.
        #expect(abs(found[0].lowerBound - 0.8) < 0.05)
        #expect(abs(found[0].upperBound - 1.3) < 0.05)
        #expect(abs(found[1].lowerBound - 3.45) < 0.05)
        #expect(abs(found[1].upperBound - 4.65) < 0.05)
    }

    @Test("The composition plays back shortened")
    func compositionPlaysShortened() async throws {
        let url = try SmartSpeedAudioFixture.write(pattern: Self.shortPattern)
        defer { try? FileManager.default.removeItem(at: url) }

        let analysis = try SmartSpeedAnalyzer.analyze(url: url)
        let timeline = SmartSpeedTimeline(silences: analysis.silenceRanges, originalDuration: analysis.duration)
        let result = try await SmartSpeedCompositionBuilder.build(asset: AVURLAsset(url: url), timeline: timeline)

        // 0.5s pause trimmed to 0.2, 1.2s pause trimmed to 0.2.
        #expect(abs(timeline.timeSaved - 1.3) < 0.1)
        let compositionDuration = try await result.composition.load(.duration).seconds
        #expect(abs(compositionDuration - timeline.compositionDuration) < 0.01)

        let decodedSeconds = try await SmartSpeedAudioFixture.decodedDuration(of: result.composition)
        #expect(abs(decodedSeconds - timeline.compositionDuration) < 0.05)
    }

    @Test(
        "Benchmark: analysis, build, and seeking for a long episode",
        .enabled(if: ProcessInfo.processInfo.environment["SMART_SPEED_BENCHMARK"] != nil)
    )
    func benchmarkLongEpisode() async throws {
        let minutes = Double(ProcessInfo.processInfo.environment["SMART_SPEED_BENCHMARK_MINUTES"] ?? "") ?? 60
        let url = try SmartSpeedAudioFixture.write(pattern: SmartSpeedAudioFixture.talkShowPattern(minutes: minutes))
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = ContinuousClock()
        var report: [String] = []

        var analysis: SmartSpeedAnalysis?
        report.append("analyze=\(clock.measure { analysis = try? SmartSpeedAnalyzer.analyze(url: url) })")
        let found = try #require(analysis)

        var timeline: SmartSpeedTimeline?
        let timelineDuration = clock.measure {
            timeline = SmartSpeedTimeline(silences: found.silenceRanges, originalDuration: found.duration)
        }
        report.append("timeline=\(timelineDuration)")
        let cuts = try #require(timeline)
        report.append("silences=\(found.silences.count) cuts=\(cuts.segments.count - 1)")
        report.append(String(format: "original=%.0fs shortened=%.0fs saved=%.1f%%",
                             cuts.originalDuration, cuts.compositionDuration,
                             100 * cuts.timeSaved / cuts.originalDuration))

        let asset = AVURLAsset(url: url)
        var built: SmartSpeedCompositionBuilder.Result?
        let buildStart = clock.now
        built = try await SmartSpeedCompositionBuilder.build(asset: asset, timeline: cuts)
        report.append("build=\(clock.now - buildStart)")
        let result = try #require(built)

        let shortenedItem = AVPlayerItem(asset: result.composition)
        report.append("shortened: " + (try await Self.measurePlayback(of: shortenedItem, duration: cuts.compositionDuration)))
        report.append("original:  " + (try await Self.measurePlayback(of: AVPlayerItem(asset: asset), duration: cuts.originalDuration)))

        print("SMARTSPEED_BENCH minutes=\(Int(minutes)) " + report.joined(separator: " | "))
    }

    /// Time to ready, then seek + preroll at fixed fractions of the item.
    private static func measurePlayback(of item: AVPlayerItem, duration: TimeInterval) async throws -> String {
        let clock = ContinuousClock()
        let player = AVPlayer(playerItem: item)
        player.volume = 0

        let readyStart = clock.now
        while item.status == .unknown, clock.now - readyStart < .seconds(30) {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(item.status == .readyToPlay, "item failed: \(String(describing: item.error))")
        var parts = ["ready=\(clock.now - readyStart)"]

        var seekTimes: [Duration] = []
        for fraction in [0.9, 0.1, 0.5, 0.75, 0.25, 0.99] {
            let target = CMTime(seconds: duration * fraction, preferredTimescale: 44_100)
            let start = clock.now
            let finished = await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            _ = await player.preroll(atRate: 1)
            seekTimes.append(clock.now - start)
            try #require(finished)
        }
        let worst = seekTimes.max() ?? .zero
        let mean = seekTimes.reduce(Duration.zero, +) / seekTimes.count
        parts.append("seek+preroll mean=\(mean) worst=\(worst)")
        return parts.joined(separator: " ")
    }

    /// Speech and pauses in seconds; covers a pause across the 1s chunk
    /// boundary, one below the minimum, and one long one.
    private static let shortPattern: [SmartSpeedAudioFixture.Span] = [
        .speech(0.8), .pause(0.5), .speech(1.0), .pause(0.15),
        .speech(1.0), .pause(1.2), .speech(0.85)
    ]
}

enum SmartSpeedAudioFixture {
    enum Span {
        case speech(TimeInterval)
        case pause(TimeInterval)
    }

    static let sampleRate = 44_100.0

    /// Writes an AAC .m4a at 44.1 kHz mono: modulated tones for speech and a
    /// -70 dBFS noise floor for pauses.
    static func write(pattern: [Span]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("smart-speed-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        var random = SplitMix(seed: 7)
        var sampleIndex = 0

        for span in pattern {
            let (seconds, isSpeech): (TimeInterval, Bool) = switch span {
            case .speech(let s): (s, true)
            case .pause(let s): (s, false)
            }
            let frames = AVAudioFrameCount((seconds * sampleRate).rounded())
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
            buffer.frameLength = frames
            let samples = buffer.floatChannelData![0]
            for i in 0..<Int(frames) {
                let t = Double(sampleIndex + i) / sampleRate
                if isSpeech {
                    let envelope = 0.6 + 0.4 * sin(2 * .pi * 4 * t)
                    let tone = sin(2 * .pi * 180 * t) + 0.5 * sin(2 * .pi * 360 * t) + 0.25 * sin(2 * .pi * 720 * t)
                    samples[i] = Float(0.15 * envelope * tone)
                } else {
                    samples[i] = Float(random.nextUnit() * 0.0003)
                }
            }
            try file.write(from: buffer)
            sampleIndex += Int(frames)
        }
        return url
    }

    /// Speech bursts of 0.4–2.0s separated by pauses of 0.3–1.2s, roughly the
    /// pause density of a conversational show.
    static func talkShowPattern(minutes: Double) -> [Span] {
        var random = SplitMix(seed: 42)
        var spans: [Span] = []
        var total: TimeInterval = 0
        while total < minutes * 60 {
            let speech = 0.4 + 1.6 * abs(random.nextUnit())
            let pause = 0.3 + 0.9 * abs(random.nextUnit())
            spans += [.speech(speech), .pause(pause)]
            total += speech + pause
        }
        return spans
    }

    static func decodedDuration(of asset: AVAsset) async throws -> TimeInterval {
        let reader = try AVAssetReader(asset: asset)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ])
        reader.add(output)
        try #require(reader.startReading())

        var frames = 0
        while let sample = output.copyNextSampleBuffer() {
            frames += CMSampleBufferGetNumSamples(sample)
        }
        try #require(reader.status == .completed, "reader: \(String(describing: reader.error))")
        return Double(frames) / sampleRate
    }
}

/// Deterministic noise so fixtures and benchmark runs are reproducible.
struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// Uniform in -1...1.
    mutating func nextUnit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53) * 2 - 1
    }
}
