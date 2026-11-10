import CoreGraphics
import Testing
@testable import OpenCast

@MainActor
@Suite("Now Playing drag intent")
struct NowPlayingDragIntentTests {
    @Test("A mostly downward drag starts the card's dismiss drag")
    func downwardDragStartsDismiss() {
        #expect(NowPlayingDragIntent.shouldStartCardDismiss(translation: CGSize(width: 72, height: 54)))
    }

    @Test("A mostly sideways or upward drag does not")
    func sidewaysOrUpwardDragDoesNotStartDismiss() {
        #expect(!NowPlayingDragIntent.shouldStartCardDismiss(translation: CGSize(width: 90, height: 54)))
        #expect(!NowPlayingDragIntent.shouldStartCardDismiss(translation: CGSize(width: 0, height: -40)))
    }
}
