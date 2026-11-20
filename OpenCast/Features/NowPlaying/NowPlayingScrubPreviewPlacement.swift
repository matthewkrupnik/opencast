import SwiftUI

/// Hangs its one subview above the slider it overlays, centred on the thumb
/// but shifted to stay within the slider's width, so the scrub bubble never
/// runs off screen at either end. Being an overlay, it takes no layout space.
struct NowPlayingScrubPreviewPlacement: Layout {
    /// Keeps a long chapter title from stretching the bubble across the bar;
    /// the title truncates instead.
    static let maximumWidth: CGFloat = 260

    var thumbFraction: Double
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let centerX = NowPlayingSkipZoneRail.thumbCenterX(atFraction: thumbFraction, width: bounds.width)
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: min(bounds.width, Self.maximumWidth), height: nil))
            let width = min(size.width, bounds.width)
            subview.place(
                at: CGPoint(
                    x: bounds.minX + Self.originX(centeredOn: centerX, width: width, containerWidth: bounds.width),
                    y: bounds.minY - spacing
                ),
                anchor: .bottomLeading,
                proposal: ProposedViewSize(width: width, height: size.height)
            )
        }
    }

    /// The leading edge that centres `width` on `centerX`, clamped so the
    /// whole span stays inside `0...containerWidth`.
    static func originX(centeredOn centerX: CGFloat, width: CGFloat, containerWidth: CGFloat) -> CGFloat {
        (centerX - width / 2).clamped(to: 0...max(containerWidth - width, 0))
    }
}
