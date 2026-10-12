import Testing
@testable import OpenCast

@MainActor
@Suite("Feed checks during background playback")
struct PlaybackFeedRefreshLoopTests {
    @Test("Each interval refreshes only while playing, and the loop ends when its sleep is cancelled")
    func refreshesOnlyWhilePlaying() async {
        let playingByTick = [true, false, true]
        var tick = 0
        var sleeps: [Duration] = []
        var refreshedTicks: [Int] = []

        await PlaybackFeedRefreshLoop.run(
            interval: .seconds(5),
            shouldRefresh: { playingByTick[tick - 1] },
            refresh: { refreshedTicks.append(tick) },
            sleep: { duration in
                guard tick < playingByTick.count else {
                    throw CancellationError()
                }
                sleeps.append(duration)
                tick += 1
            }
        )

        #expect(sleeps == [.seconds(5), .seconds(5), .seconds(5)])
        #expect(refreshedTicks == [1, 3])
    }

    @Test("The first check waits a full interval after going to the background")
    func firstCheckWaitsAnInterval() async {
        var refreshCount = 0

        await PlaybackFeedRefreshLoop.run(
            shouldRefresh: { true },
            refresh: { refreshCount += 1 },
            sleep: { duration in
                #expect(duration == PlaybackFeedRefreshLoop.interval)
                throw CancellationError()
            }
        )

        #expect(refreshCount == 0)
    }
}
