import AVFoundation

nonisolated final class RateController: @unchecked Sendable {
    private let settings: SmartSpeedSettings
    private let onRateChanged: (Float) -> Void
    private let silenceMap: SilenceMap
    private let musicDetector: MusicDetector?
    private var currentRate: Double = 1.0
    
    // Closure to get current media frame dynamically
    @MainActor var currentMediaFrame: (@MainActor () -> AVAudioFramePosition?)?

    init(settings: SmartSpeedSettings, silenceMap: SilenceMap, musicDetector: MusicDetector?, onRateChanged: @escaping (Float) -> Void) {
        self.settings = settings
        self.silenceMap = silenceMap
        self.musicDetector = musicDetector
        self.onRateChanged = onRateChanged
        self.currentRate = settings.baselineSpeed
    }

    @MainActor func tick() {
        let base = settings.baselineSpeed
        var target = base

        if settings.enabled && !(settings.musicDetectionEnabled && (musicDetector?.isMusic ?? false)) {
            if let frame = currentMediaFrame?() {
                target = silenceMap.isSilence(atFrame: frame) ? settings.silenceSkipSpeed : base
            }
        }
        
        // Ramp to avoid audible "step" artifacts
        let step = settings.rampStepPerTick
        if currentRate < target {
            currentRate = min(currentRate + step, target)
        } else if currentRate > target {
            currentRate = max(currentRate - step, target)
        }
        
        onRateChanged(Float(currentRate))
    }
}