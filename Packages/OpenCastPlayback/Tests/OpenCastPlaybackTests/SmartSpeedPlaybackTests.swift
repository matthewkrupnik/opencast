import AVFoundation
import Foundation
import Testing
@testable import OpenCastPlayback

@MainActor
@Suite("Smart Speed playback")
struct SmartSpeedPlaybackTests {
    @Test("A download plays its trimmed copy while every reported time stays on the episode clock")
    func trimmedCopyKeepsEpisodeClock() async throws {
        try await AVFoundationPlaybackTestGate.acquire()
        defer { AVFoundationPlaybackTestGate.release() }
        let url = try SmartSpeedAudioFixture.write(pattern: Self.pattern)
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = AVFoundationPlaybackController()
        defer { controller.unload() }
        var events: [String] = []
        controller.setEventLogHandler { events.append($0) }
        controller.setSmartSpeedEnabled(true)

        var current = episode(duration: nil)
        current.audioURL = url
        try controller.load(current, startPosition: 3)
        try await waitUntil { events.contains { $0.contains("smart speed trimmed") } }

        // 0.5s and 1.2s pauses trimmed to 0.2s each; the 0.15s one is kept.
        #expect(abs(try #require(controller.duration) - 5.5) < 0.05)
        #expect(abs(controller.position - 3) < 0.05)
        #expect(controller.state == .paused)
        #expect(controller.currentItemSourceIdentity?.assetURL == url)
        #expect(abs(try #require(controller.currentItemSourceIdentity?.itemDuration) - 5.5) < 0.05)
        try await waitForMediaClock(in: controller, near: 3)

        // After the long pause, the player is 1.3s behind the episode clock.
        controller.seek(to: 4.8)
        try await waitForMediaClock(in: controller, near: 4.8)

        controller.setSmartSpeedEnabled(false)
        #expect(events.last?.contains("smart speed off") == true)
        #expect(abs(controller.position - 4.8) < 0.05)
        try await waitForMediaClock(in: controller, near: 4.8)

        // Turning it back on reuses the analysis instead of decoding again.
        controller.setSmartSpeedEnabled(true)
        #expect(events.last?.contains("smart speed trimmed") == true)
        try await waitForMediaClock(in: controller, near: 4.8)
    }

    @Test("The trimmed copy plays through Voice Boost")
    func trimmedCopyPlays() async throws {
        try await AVFoundationPlaybackTestGate.acquire()
        defer { AVFoundationPlaybackTestGate.release() }
        let url = try SmartSpeedAudioFixture.write(pattern: Self.pattern)
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = AVFoundationPlaybackController()
        defer { controller.unload() }
        var events: [String] = []
        controller.setEventLogHandler { events.append($0) }
        controller.setSmartSpeedEnabled(true)
        controller.setVoiceBoostEnabled(true)

        var current = episode(duration: nil)
        current.audioURL = url
        try controller.load(current)
        try await waitUntil { events.contains { $0.contains("smart speed trimmed") } }
        #expect(events.last { $0.contains("voice boost installed") }?.contains("enabled=true") == true)
        controller.play()
        try await waitUntil { controller.state == .playing }
        try await waitUntil { controller.position > 1.3 }
    }

    @Test("Streams play unchanged")
    func streamsAreNotTrimmed() async throws {
        let controller = AVFoundationPlaybackController()
        defer { controller.unload() }
        var events: [String] = []
        controller.setEventLogHandler { events.append($0) }
        controller.setSmartSpeedEnabled(true)
        try controller.load(episode(duration: 240), startPosition: 30)

        #expect(!events.contains { $0.contains("smart speed") })
        #expect(controller.currentItemSourceIdentity?.kind == .networkStream)
    }

    private static let pattern: [SmartSpeedAudioFixture.Span] = [
        .speech(0.8), .pause(0.5), .speech(1.0), .pause(0.15),
        .speech(1.0), .pause(1.2), .speech(0.85)
    ]

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(10)
        while !condition() {
            try #require(Date.now < deadline, "timed out")
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func waitForMediaClock(
        in controller: AVFoundationPlaybackController,
        near position: TimeInterval
    ) async throws {
        var last: TimeInterval?
        let deadline = Date.now.addingTimeInterval(5)
        while Date.now < deadline {
            for await sample in controller.mediaClockSamples() {
                last = sample.position
                break
            }
            if let last, abs(last - position) < 0.05 {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("media clock at \(String(describing: last)), expected \(position)")
    }
}
