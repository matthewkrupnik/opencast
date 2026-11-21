import Testing
@testable import OpenCastPlayback

@Suite("PlaybackSeekIntent")
struct PlaybackSeekIntentTests {
    @Test("Chapter jumps and restores land exactly; the rest tolerate")
    func landsExactly() {
        #expect(PlaybackSeekIntent.chapter.landsExactly)
        #expect(PlaybackSeekIntent.restore.landsExactly)
        #expect(!PlaybackSeekIntent.scrub.landsExactly)
        #expect(!PlaybackSeekIntent.skipButton.landsExactly)
        #expect(!PlaybackSeekIntent.autoSkip.landsExactly)
    }

    @Test("Only scrubs and chapter jumps are kept for undoing")
    func recordsSeekHistory() {
        #expect(PlaybackSeekIntent.scrub.recordsSeekHistory)
        #expect(PlaybackSeekIntent.chapter.recordsSeekHistory)
        #expect(!PlaybackSeekIntent.skipButton.recordsSeekHistory)
        #expect(!PlaybackSeekIntent.autoSkip.recordsSeekHistory)
        #expect(!PlaybackSeekIntent.restore.recordsSeekHistory)
    }
}
