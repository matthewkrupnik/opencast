import AVFoundation
import QuartzCore

extension AVAudioPCMBuffer: @unchecked Sendable {}

nonisolated final class SmartSpeedEngine: @unchecked Sendable {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let timePitch = AVAudioUnitTimePitch()
    let decoder: PCMDecoder
    let silenceMap = SilenceMap()
    let detector: SilenceDetector
    let musicDetector: MusicDetector?
    let speedometer = Speedometer()
    var settings: SmartSpeedSettings {
        didSet {
            // Update dependencies if settings change, like baseline speed.
            // For a full implementation, you'd probably recreate detector or just pass settings down.
        }
    }

    private var rateController: RateController?
    private var controlTimer: Timer?
    
    // Resume state
    struct SmartResumeState {
        var pausedMediaFrame: AVAudioFramePosition
        var pausedAt: Date
    }
    var resumeState: SmartResumeState?

    init(url: URL, settings: SmartSpeedSettings) throws {
        self.settings = settings
        self.decoder = try PCMDecoder(url: url)
        
        let fmt = decoder.format
        self.detector = SilenceDetector(settings: settings, sampleRate: fmt.sampleRate)
        self.musicDetector = MusicDetector(format: fmt, threshold: settings.musicBypassConfidence)
        
        timePitch.overlap = 8 // Better quality for speech
    }

    func start() throws {
        engine.attach(player)
        engine.attach(timePitch)
        
        engine.connect(player, to: timePitch, format: decoder.format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: decoder.format)
        
        engine.prepare()
        try engine.start()

        rateController = RateController(settings: settings, silenceMap: silenceMap, musicDetector: musicDetector) { [weak self] rate in
            self?.timePitch.rate = rate
        }
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.rateController?.currentMediaFrame = { [weak self] in
                self?.currentMediaFrame()
            }
        }
        
        startScheduling()
        player.play()
        startControlLoop()
    }
    
    func pause() {
        if let frame = currentMediaFrame() {
            resumeState = SmartResumeState(pausedMediaFrame: frame, pausedAt: Date())
        }
        player.pause()
        controlTimer?.invalidate()
        controlTimer = nil
    }
    
    func resumeWithSmartResume() {
        guard let state = resumeState else {
            player.play()
            startControlLoop()
            return
        }
        
        let windowFrames = AVAudioFramePosition(settings.smartResumeWindow * decoder.format.sampleRate)
        let lookback = min(windowFrames, state.pausedMediaFrame)
        let target = silenceMap.nearestSilenceEnd(before: state.pausedMediaFrame)
            ?? (state.pausedMediaFrame - lookback)
        
        decoder.seek(toFrame: target)
        player.stop()
        
        // We need to flush the lookahead buffer here in a real implementation
        // and restart scheduling from `target`.
        startScheduling()
        player.play()
        
        resumeState = nil
        startControlLoop()
    }
    
    func shouldSmartComplete() -> Bool {
        guard musicDetector?.isMusic == true else { return false }
        guard let current = currentMediaFrame() else { return false }
        
        let remaining = Double(decoder.fileLength - current) / decoder.format.sampleRate
        return remaining <= settings.smartCompleteTail
    }

    private func currentMediaFrame() -> AVAudioFramePosition? {
        guard let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return nil }
        return playerTime.sampleTime
    }

    // Background: decode → feed detector + music detector → schedule on player.
    private func startScheduling() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let chunkFrames = AVAudioFrameCount(self.decoder.format.sampleRate) // 1s chunks
            // let lookaheadSeconds = 5 // Not explicitly used right now, but we'd bound the buffer in a real app
            
            while true {
                guard let buf = AVAudioPCMBuffer(pcmFormat: self.decoder.format,
                                                 frameCapacity: chunkFrames) else { break }
                
                let more = self.decoder.read(into: buf, maxFrames: chunkFrames)
                guard buf.frameLength > 0 else { break }

                // Lookahead analysis
                let currentFrameOffset = self.decoder.file.framePosition - AVAudioFramePosition(buf.frameLength)
                let regions = self.detector.detect(in: buf, frameOffset: currentFrameOffset)
                self.silenceMap.append(regions)
                self.musicDetector?.feed(buf, atAudioFramePosition: currentFrameOffset)

                // Schedule for playback
                self.player.scheduleBuffer(buf)
                
                if !more { break }
                
                // Add backpressure here if player queue gets too far ahead (lookahead > 5s)
            }
        }
    }

    private func startControlLoop() {
        controlTimer?.invalidate()
        controlTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.rateController?.tick()
            
            if let frame = self.currentMediaFrame() {
                let mediaSeconds = Double(frame) / self.decoder.format.sampleRate
                self.speedometer.update(mediaSeconds: mediaSeconds, realSeconds: CACurrentMediaTime())
            }
            
            if self.shouldSmartComplete() {
                // Handle Smart Complete (stop playback, mark as finished)
                self.player.stop()
                self.controlTimer?.invalidate()
            }
        }
    }
}