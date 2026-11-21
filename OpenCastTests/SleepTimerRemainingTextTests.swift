import Foundation
import OpenCastPlayback
import Testing
@testable import OpenCast

@MainActor
@Suite
struct SleepTimerRemainingTextTests {
    @Test(arguments: [
        (PlaybackSleepTimerMode.off, nil as TimeInterval?, "Off"),
        (.endOfEpisode, nil, "Stop After This Episode"),
        (.endOfEpisode, 125, "-2:05"),
        (.duration(900), 899, "-14:59"),
        (.duration(900), 0, "Off")
    ])
    func describesTheTimerState(mode: PlaybackSleepTimerMode, remaining: TimeInterval?, expected: String) {
        #expect(SleepTimerRemainingText.text(mode: mode, remaining: remaining) == expected)
    }

    @Test(arguments: [
        (PlaybackSleepTimerMode.off, nil as TimeInterval?, nil as String?),
        (.endOfEpisode, 125, nil),
        (.duration(900), 899, "15m"),
        (.duration(900), 841, "15m"),
        (.duration(900), 840, "14m"),
        (.duration(900), 61, "2m"),
        (.duration(900), 60, "1:00"),
        (.duration(900), 45.4, "0:45"),
        (.duration(900), 0, nil)
    ])
    func toolbarCountdown(mode: PlaybackSleepTimerMode, remaining: TimeInterval?, expected: String?) {
        #expect(SleepTimerRemainingText.toolbarText(mode: mode, remaining: remaining) == expected)
    }

    @Test(arguments: [
        (PlaybackSleepTimerMode.off, nil as TimeInterval?, nil as String?),
        (.endOfEpisode, 125, "sleep timer, stops after this episode"),
        (.duration(900), 0, nil)
    ])
    func spokenState(mode: PlaybackSleepTimerMode, remaining: TimeInterval?, expected: String?) {
        #expect(SleepTimerRemainingText.spokenText(mode: mode, remaining: remaining) == expected)
    }

    @Test("A running timer is spoken in rounded-up minutes, then seconds")
    func spokenCountdown() throws {
        let minutes = try #require(SleepTimerRemainingText.spokenText(mode: .duration(900), remaining: 841))
        let seconds = try #require(SleepTimerRemainingText.spokenText(mode: .duration(900), remaining: 44.2))
        #expect(minutes.hasPrefix("sleep timer, ") && minutes.contains("15") && minutes.hasSuffix(" left"))
        #expect(seconds.contains("45") && !seconds.contains("min"))
    }
}
