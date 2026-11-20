import OpenCastPlayback
import Testing
@testable import OpenCast

@Suite("Playback media origin")
struct PlaybackMediaOriginTests {
    @Test
    func localFileItemIsDownloaded() {
        #expect(PlaybackMediaOrigin(itemKind: .localFile) == .downloaded)
    }

    @Test
    func networkStreamItemIsStreaming() {
        #expect(PlaybackMediaOrigin(itemKind: .networkStream) == .streaming)
    }

    @Test
    func noLoadedItemHasNoOrigin() {
        #expect(PlaybackMediaOrigin(itemKind: nil) == nil)
    }
}
