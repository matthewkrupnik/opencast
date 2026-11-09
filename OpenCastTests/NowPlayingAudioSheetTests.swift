import Testing
@testable import OpenCast

@MainActor
@Suite("Now Playing Audio sheet speed steps")
struct NowPlayingAudioSheetTests {
    @Test("Steps move one notch and stop at either end instead of wrapping")
    func stepsStopAtTheEnds() {
        #expect(NowPlayingAudioSheet.faster(than: 1) == 1.25)
        #expect(NowPlayingAudioSheet.slower(than: 1) == 0.75)
        #expect(NowPlayingAudioSheet.faster(than: 2) == nil)
        #expect(NowPlayingAudioSheet.slower(than: 0.75) == nil)
    }

    @Test("An off-step speed moves to the nearest step in that direction")
    func offStepSpeedSnapsToNeighbor() {
        #expect(NowPlayingAudioSheet.faster(than: 1.1) == 1.25)
        #expect(NowPlayingAudioSheet.slower(than: 1.1) == 1)
        #expect(NowPlayingAudioSheet.faster(than: 2.5) == nil)
        #expect(NowPlayingAudioSheet.slower(than: 2.5) == 2)
        #expect(NowPlayingAudioSheet.slower(than: 0.5) == nil)
    }

    @Test("A speed that round-tripped through Float arithmetic does not select itself")
    func toleranceSkipsTheCurrentStep() {
        let nearlyOneAndAHalf: Float = 1.5 + 0.00001
        #expect(NowPlayingAudioSheet.faster(than: nearlyOneAndAHalf) == 1.75)
        #expect(NowPlayingAudioSheet.slower(than: nearlyOneAndAHalf) == 1.25)
    }
}
