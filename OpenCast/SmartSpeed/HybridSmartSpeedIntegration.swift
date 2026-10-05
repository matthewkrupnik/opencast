import AVFoundation
import OpenCastPlayback

nonisolated final class HybridSmartSpeedIntegration: @unchecked Sendable {
    private let controller: AVFoundationPlaybackController
    private let decoder: PCMDecoder
    private let detector: SilenceDetector
    private let musicDetector: MusicDetector?
    private let silenceMap = SilenceMap()
    private let settings: SmartSpeedSettings
    private var rateController: RateController?
    private var controlTimer: Timer?
    private var analysisTask: Task<Void, Never>?
    private var isEnabled: Bool = false
    private let baseRateProvider: () -> Float

    init?(controller: AVFoundationPlaybackController, url: URL, settings: SmartSpeedSettings, baseRateProvider: @escaping () -> Float) {
        guard url.isFileURL else { return nil }
        self.controller = controller
        self.settings = settings
        self.baseRateProvider = baseRateProvider
        
        do {
            self.decoder = try PCMDecoder(url: url)
            let fmt = decoder.format
            self.detector = SilenceDetector(settings: settings, sampleRate: fmt.sampleRate)
            self.musicDetector = MusicDetector(format: fmt, threshold: settings.musicBypassConfidence)
        } catch {
            return nil
        }

        self.rateController = RateController(settings: settings, silenceMap: silenceMap, musicDetector: musicDetector) { [weak self] rate in
            guard let self = self, self.isEnabled else { return }
            // Dispatch to MainActor because AVFoundationPlaybackController is @MainActor
            Task { @MainActor in
                self.controller.setInternalRate(rate)
            }
        }
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.rateController?.currentMediaFrame = { [weak self] in
                guard let self = self else { return nil }
                return AVAudioFramePosition(self.controller.position * self.decoder.format.sampleRate)
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
        if enabled {
            startAnalysis()
            startControlLoop()
        } else {
            stopControlLoop()
            Task { @MainActor in
                self.controller.setInternalRate(self.baseRateProvider())
            }
        }
    }
    
    private func startAnalysis() {
        guard analysisTask == nil else { return }
        analysisTask = Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            let chunkFrames = AVAudioFrameCount(self.decoder.format.sampleRate)
            while !Task.isCancelled {
                guard let buf = AVAudioPCMBuffer(pcmFormat: self.decoder.format, frameCapacity: chunkFrames) else { break }
                let more = self.decoder.read(into: buf, maxFrames: chunkFrames)
                guard buf.frameLength > 0 else { break }

                let currentFrameOffset = self.decoder.file.framePosition - AVAudioFramePosition(buf.frameLength)
                let regions = self.detector.detect(in: buf, frameOffset: currentFrameOffset)
                self.silenceMap.append(regions)
                self.musicDetector?.feed(buf, atAudioFramePosition: currentFrameOffset)

                if !more { break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }

    private func startControlLoop() {
        controlTimer?.invalidate()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.controlTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    if self.controller.state == .playing {
                        self.rateController?.tick()
                    }
                }
            }
        }
    }

    private func stopControlLoop() {
        controlTimer?.invalidate()
        controlTimer = nil
    }
    
    deinit {
        analysisTask?.cancel()
        controlTimer?.invalidate()
    }
}
