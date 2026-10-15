import AVFoundation

/// Silence found by decoding a whole downloaded file ahead of playback.
nonisolated struct SmartSpeedAnalysis: Sendable, Codable {
    let sampleRate: Double
    let frameCount: AVAudioFramePosition
    let silences: [SilenceRegion]

    var duration: TimeInterval {
        Double(frameCount) / sampleRate
    }

    var silenceRanges: [ClosedRange<TimeInterval>] {
        silences.map { Double($0.startFrame) / sampleRate ... Double($0.endFrame) / sampleRate }
    }
}

nonisolated enum SmartSpeedAnalyzer {
    static func analyze(url: URL) throws -> SmartSpeedAnalysis {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let detector = SilenceDetector(sampleRate: format.sampleRate)
        let chunkFrames = AVAudioFrameCount(format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw CocoaError(.fileReadUnknown)
        }

        var silences: [SilenceRegion] = []
        while file.framePosition < file.length {
            try Task.checkCancellation()
            let offset = file.framePosition
            try file.read(into: buffer, frameCount: chunkFrames)
            guard buffer.frameLength > 0 else { break }
            silences += detector.detect(in: buffer, frameOffset: offset)
        }
        silences += detector.finish()

        return SmartSpeedAnalysis(
            sampleRate: format.sampleRate,
            frameCount: file.length,
            silences: silences
        )
    }
}
