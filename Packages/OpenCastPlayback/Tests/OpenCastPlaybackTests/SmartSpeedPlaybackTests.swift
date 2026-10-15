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
        let url = try Self.writeFixture()
        defer { Self.remove(url) }
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
        let url = try Self.writeFixture()
        defer { Self.remove(url) }
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

    @Test("Saved pauses are reused only for the file they were found in")
    func pauseFileMatchesItsDownload() throws {
        let url = try Self.writeFixture()
        defer { Self.remove(url) }

        #expect(SmartSpeedPauseFile.load(for: url) == nil)
        let found = try SmartSpeedPauseFile.analyzeAndSave(for: url)
        let saved = try #require(SmartSpeedPauseFile.load(for: url))
        #expect(saved.silenceRanges == found.silenceRanges)
        #expect(saved.duration == found.duration)

        // A replacement download at the same path must be analyzed again.
        let replacement = try Self.writeFixture()
        defer { Self.remove(replacement) }
        try FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: replacement, to: url)
        #expect(SmartSpeedPauseFile.load(for: url) == nil)
    }

    @Test("With saved pauses, playback starts on the trimmed copy instead of swapping to it")
    func savedPausesStartTrimmed() async throws {
        try await AVFoundationPlaybackTestGate.acquire()
        defer { AVFoundationPlaybackTestGate.release() }
        let url = try Self.writeFixture()
        defer { Self.remove(url) }
        await SmartSpeedPausePreparer.shared.preparePauses(for: url)
        #expect(SmartSpeedPauseFile.load(for: url) != nil)

        let controller = AVFoundationPlaybackController()
        defer { controller.unload() }
        var events: [String] = []
        controller.setEventLogHandler { events.append($0) }
        controller.setSmartSpeedEnabled(true)
        var current = episode(duration: nil)
        current.audioURL = url
        try controller.load(current, startPosition: 3)
        controller.play()
        try await waitUntil { controller.state == .playing }

        let trimmed = try #require(events.firstIndex { $0.contains("smart speed trimmed") })
        let started = try #require(events.firstIndex { $0.contains("requested ready item playback") })
        #expect(trimmed < started, "\(events)")
        #expect(abs(try #require(controller.duration) - 5.5) < 0.05)
        #expect(controller.position > 2.95)
    }

    @Test("Unusable saved pauses fall back to playing the file while analyzing")
    func stalePauseFileDoesNotHoldPlayback() async throws {
        try await AVFoundationPlaybackTestGate.acquire()
        defer { AVFoundationPlaybackTestGate.release() }
        let url = try Self.writeFixture()
        defer { Self.remove(url) }
        try Data("stale".utf8).write(to: SmartSpeedPauseFile.url(for: url))

        let controller = AVFoundationPlaybackController()
        defer { controller.unload() }
        var events: [String] = []
        controller.setEventLogHandler { events.append($0) }
        controller.setSmartSpeedEnabled(true)
        var current = episode(duration: nil)
        current.audioURL = url
        try controller.load(current)
        controller.play()
        try await waitUntil { events.contains { $0.contains("smart speed trimmed") } }
        try await waitUntil { controller.state == .playing }
        #expect(SmartSpeedPauseFile.load(for: url) != nil)
    }

    @Test("Turned on mid-play, the swap waits for the next pause and the state stays playing")
    func midPlaySwapLandsInAPause() async throws {
        try await AVFoundationPlaybackTestGate.acquire()
        defer { AVFoundationPlaybackTestGate.release() }
        let url = try SmartSpeedAudioFixture.write(pattern: [
            .speech(2.0), .pause(0.6), .speech(1.5), .pause(1.0), .speech(1.0)
        ])
        defer { Self.remove(url) }
        let controller = AVFoundationPlaybackController()
        defer { controller.unload() }
        var events: [String] = []
        controller.setEventLogHandler { events.append($0) }
        var current = episode(duration: nil)
        current.audioURL = url
        try controller.load(current)
        controller.play()
        try await waitUntil { controller.state == .playing }

        controller.setSmartSpeedEnabled(true)
        var interruptions: [PlaybackState] = []
        let deadline = Date.now.addingTimeInterval(10)
        while !events.contains(where: { $0.contains("smart speed swap resumed") }) {
            try #require(Date.now < deadline, "\(events)")
            if controller.state != .playing {
                interruptions.append(controller.state)
            }
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(interruptions.isEmpty, "\(interruptions) \(events)")
        // The 2.0–2.6 pause is cut from 2.1 to 2.5.
        let cutStart = try #require(Self.time(after: "swap waits for cut at ", in: events))
        #expect(abs(cutStart - 2.1) < 0.06, "\(events)")
        let resumedAt = try #require(Self.time(after: "rebuilt player item at ", in: events))
        #expect(abs(resumedAt - 2.5) < 0.06, "\(events)")
        print("SMARTSPEED_SWAP", events.first { $0.contains("swap resumed") } ?? "")
        try await waitForMediaClock(in: controller, near: 2.6, tolerance: 0.4)
    }

    @Test("Pausing before the pause arrives swaps right away")
    func pauseSwapsImmediately() async throws {
        try await AVFoundationPlaybackTestGate.acquire()
        defer { AVFoundationPlaybackTestGate.release() }
        let url = try SmartSpeedAudioFixture.write(pattern: [.speech(3.0), .pause(0.6), .speech(1.0)])
        defer { Self.remove(url) }
        let controller = AVFoundationPlaybackController()
        defer { controller.unload() }
        var events: [String] = []
        controller.setEventLogHandler { events.append($0) }
        var current = episode(duration: nil)
        current.audioURL = url
        try controller.load(current)
        controller.play()
        try await waitUntil { controller.state == .playing }
        controller.setSmartSpeedEnabled(true)
        try await waitUntil { events.contains { $0.contains("smart speed swap waits for cut") } }

        controller.pause()
        #expect(events.last?.contains("smart speed trimmed") == true, "\(events)")
        #expect(controller.state == .paused)
        #expect(!events.contains { $0.contains("smart speed swap resumed") })
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

    private static func time(after marker: String, in events: [String]) -> TimeInterval? {
        guard let event = events.last(where: { $0.contains(marker) }),
              let range = event.range(of: marker)
        else {
            return nil
        }
        return TimeInterval(event[range.upperBound...].prefix { $0.isNumber || $0 == "." })
    }

    private static func writeFixture() throws -> URL {
        try SmartSpeedAudioFixture.write(pattern: pattern)
    }

    private static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: SmartSpeedPauseFile.url(for: url))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(10)
        while !condition() {
            try #require(Date.now < deadline, "timed out")
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func waitForMediaClock(
        in controller: AVFoundationPlaybackController,
        near position: TimeInterval,
        tolerance: TimeInterval = 0.05
    ) async throws {
        var last: TimeInterval?
        let deadline = Date.now.addingTimeInterval(5)
        while Date.now < deadline {
            for await sample in controller.mediaClockSamples() {
                last = sample.position
                break
            }
            if let last, abs(last - position) < tolerance {
                // Let position ticks already queued for the main actor
                // land first; one captured before a seek the test makes
                // next can otherwise read as that seek's landing.
                try await Task.sleep(for: .milliseconds(50))
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("media clock at \(String(describing: last)), expected \(position)")
    }
}
