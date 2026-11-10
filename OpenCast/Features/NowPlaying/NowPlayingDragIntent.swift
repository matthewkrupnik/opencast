import CoreGraphics

enum NowPlayingDragIntent {
    /// A drag starts the card's dismiss drag when it moves down more than
    /// sideways.
    static func shouldStartCardDismiss(translation: CGSize) -> Bool {
        translation.height > 0 && translation.height > abs(translation.width) * 0.7
    }
}
