import AVFoundation

final class RateController: @unchecked Sendable {
    private let settings: SmartSpeedSettings
    private let timePitch: AVAudioUnitTimePitch
    private let silenceMap: SilenceMap
    private let musicDetector: MusicDetector?
    private var currentRate: Double = 1.0
    
    // Closure to get current media frame dynamically
    var currentMediaFrame: (() -> AVAudioFramePosition?)?

    init(settings: SmartSpeedSettings, timePitch: AVAudioUnitTimePitch,
         silenceMap: SilenceMap, musicDetector: MusicDetector?) {
        self.settings = settings
        self.timePitch = timePitch
        self.silenceMap = silenceMap
        self.musicDetector = musicDetector
        self.currentRate = settings.baselineSpeed
    }

    func tick() {
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
        
        timePitch.rate = Float(currentRate)
    }
}