import Foundation
@testable import OpenCast

@MainActor
final class PlaybackVoiceBoostControllerSpy: @MainActor PlaybackSettingsControlling {
    private(set) var rate: Float = 1
    private(set) var appliedRates: [Float] = []
    private(set) var appliedValues: [Bool] = []
    private(set) var appliedSkipIntervals: [(backward: TimeInterval, forward: TimeInterval)] = []
    private(set) var appliedAutoSkipValues: [Bool] = []
    private(set) var appliedSmartSpeedValues: [Bool] = []

    func setRate(_ rate: Float) {
        self.rate = rate
        appliedRates.append(rate)
    }

    func setVoiceBoostEnabled(_ isEnabled: Bool) {
        appliedValues.append(isEnabled)
    }

    func setSkipIntervals(backward: TimeInterval, forward: TimeInterval) {
        appliedSkipIntervals.append((backward, forward))
    }

    func setSmartSpeedEnabled(_ isEnabled: Bool) {
        appliedSmartSpeedValues.append(isEnabled)
    }

    func setAutoSkipEnabled(_ isEnabled: Bool) {
        appliedAutoSkipValues.append(isEnabled)
    }
}
