import AVFoundation
import SoundAnalysis

nonisolated final class MusicDetector: NSObject, SNResultsObserving, @unchecked Sendable {
    private let analyzer: SNAudioStreamAnalyzer
    private let request: SNClassifySoundRequest?
    private let threshold: Double
    private(set) var isMusic = false

    init?(format: AVAudioFormat, threshold: Double) {
        self.threshold = threshold
        self.analyzer = SNAudioStreamAnalyzer(format: format)
        self.request = try? SNClassifySoundRequest(classifierIdentifier: .version1)
        super.init()
        if let request = request {
            request.windowDuration = CMTime(seconds: 1.0, preferredTimescale: 48000)
            request.overlapFactor = 0.5
            try? analyzer.add(request, withObserver: self)
        }
    }

    func feed(_ buffer: AVAudioPCMBuffer, atAudioFramePosition position: AVAudioFramePosition) {
        analyzer.analyze(buffer, atAudioFramePosition: position)
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult,
              let music = r.classification(forIdentifier: "music") else { return }
        isMusic = music.confidence > threshold
    }
}