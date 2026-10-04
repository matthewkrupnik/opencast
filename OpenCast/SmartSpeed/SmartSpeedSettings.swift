import Foundation

struct SmartSpeedSettings: Sendable {
    var enabled = true
    var baselineSpeed: Double = 1.0        // user speed (1.0, 1.25, 1.5, 2.0…)
    var silenceSkipSpeed: Double = 2.5     // rate during silence
    var silenceThresholdDBFS: Double = -45.0
    var minimumSilenceDuration: TimeInterval = 0.25
    var attackDuration: TimeInterval = 0.05   // hysteresis (noise-gate style)
    var releaseDuration: TimeInterval = 0.15
    var musicDetectionEnabled = true
    var musicBypassConfidence: Double = 0.6
    var rampStepPerTick: Double = 0.03        // rate smoothing to avoid artifacts
    var smartResumeWindow: TimeInterval = 30.0 // max look-back on resume
    var smartCompleteTail: TimeInterval = 30.0 // tail window to detect outro
}