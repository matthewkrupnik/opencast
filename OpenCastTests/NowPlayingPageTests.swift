import Testing
@testable import OpenCast

@Suite("Now Playing pages")
struct NowPlayingPageTests {
    @Test("The artwork always leads; chapters and transcript join when present")
    func pageList() {
        #expect(NowPlayingPage.pages(hasChapters: false, hasTranscript: false) == [.artwork])
        #expect(NowPlayingPage.pages(hasChapters: true, hasTranscript: false) == [.artwork, .chapters])
        #expect(NowPlayingPage.pages(hasChapters: false, hasTranscript: true) == [.artwork, .transcript])
        #expect(NowPlayingPage.pages(hasChapters: true, hasTranscript: true) == [.artwork, .chapters, .transcript])
    }

    @Test("A selection whose page went away falls back to the artwork")
    func resolvedSelection() {
        #expect(NowPlayingPage.resolved(.chapters, in: [.artwork, .transcript]) == .artwork)
        #expect(NowPlayingPage.resolved(.transcript, in: [.artwork]) == .artwork)
        #expect(NowPlayingPage.resolved(.transcript, in: [.artwork, .chapters, .transcript]) == .transcript)
    }

    @Test("Neighbors stop at either end")
    func neighbors() {
        let pages: [NowPlayingPage] = [.artwork, .chapters, .transcript]
        #expect(NowPlayingPage.artwork.neighbor(1, in: pages) == .chapters)
        #expect(NowPlayingPage.transcript.neighbor(-1, in: pages) == .chapters)
        #expect(NowPlayingPage.artwork.neighbor(-1, in: pages) == nil)
        #expect(NowPlayingPage.transcript.neighbor(1, in: pages) == nil)
        #expect(NowPlayingPage.chapters.neighbor(1, in: [.artwork]) == nil)
    }
}
