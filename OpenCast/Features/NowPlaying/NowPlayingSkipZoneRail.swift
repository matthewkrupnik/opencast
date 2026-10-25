import OpenCastPlayback
import SwiftUI

/// Skip zones and chapter dots drawn over the stock slider's track, so they
/// read as part of the bar. The stock track can't be restyled, so this is laid
/// over the slider; times map onto the thumb's travel range, and the thumb's
/// own footprint is left clear so the marks never paint across it.
struct NowPlayingSkipZoneRail: View {
    private static let minimumZoneWidth: CGFloat = 2
    private static let stripeSpacing: CGFloat = 6
    private static let markerDiameter: CGFloat = 3
    /// The stock slider's track and thumb on iOS 26 and later. The thumb's
    /// centre travels from half its width in from each end, and the fill
    /// ends at that centre.
    private static let trackHeight: CGFloat = 6
    private static let thumbSize = CGSize(width: 38, height: 26)

    let duration: TimeInterval
    let zones: [PlaybackSkipZone]
    let displayOnlyZones: [PlaybackSkipZone]
    /// Chapter start times, drawn as dots so they read like the stock
    /// slider's ticks without changing the slider itself.
    var chapterMarkers: [TimeInterval] = []
    /// Where the thumb sits, as a fraction of the track, so its area is left
    /// clear.
    var thumbFraction: Double = 0

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Canvas { context, size in
            var rail = context
            rail.clip(to: Path(thumbClearance(in: size)), options: .inverse)
            drawZones(displayOnlyZones, dimmed: true, in: &rail, size: size)
            drawZones(zones, dimmed: false, in: &rail, size: size)
            drawChapterMarkers(in: &rail, size: size)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawZones(
        _ zones: [PlaybackSkipZone],
        dimmed: Bool,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard duration.isFinite, duration > 0, size.width > 0, size.height > 0 else {
            return
        }

        let fill = Color.red.opacity(dimmed ? 0.26 : 0.72)
        let stripe = Color.white.opacity(dimmed ? 0.35 : 0.75)

        for zone in zones {
            guard let rect = rect(for: zone, size: size) else {
                continue
            }

            let shape = Path(roundedRect: rect, cornerRadius: rect.height / 2)
            context.fill(shape, with: .color(fill))

            if differentiateWithoutColor {
                var stripedContext = context
                stripedContext.clip(to: shape)
                stripedContext.stroke(stripePath(in: rect), with: .color(stripe), lineWidth: 1)
            }
        }
    }

    private func drawChapterMarkers(in context: inout GraphicsContext, size: CGSize) {
        guard duration.isFinite, duration > 0, size.width > 0, size.height > 0 else {
            return
        }

        let diameter = min(Self.markerDiameter, Self.trackHeight)
        for marker in chapterMarkers {
            let x = xPosition(for: marker, width: size.width)
            let rect = CGRect(
                x: (x - diameter / 2).clamped(to: 0...max(size.width - diameter, 0)),
                y: (size.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            context.fill(Path(ellipseIn: rect), with: .color(.secondary))
        }
    }

    private func rect(for zone: PlaybackSkipZone, size: CGSize) -> CGRect? {
        let startX = xPosition(for: zone.startTime, width: size.width)
        let endX = xPosition(for: zone.endTime, width: size.width)
        let rawWidth = endX - startX
        guard rawWidth > 0 else {
            return nil
        }

        let visualWidth = min(size.width, max(rawWidth, Self.minimumZoneWidth))
        let x = min(max(0, startX), max(0, size.width - visualWidth))
        let height = min(Self.trackHeight, size.height)
        return CGRect(x: x, y: (size.height - height) / 2, width: visualWidth, height: height)
    }

    private func xPosition(for time: TimeInterval, width: CGFloat) -> CGFloat {
        let clampedTime = time.clamped(to: 0...duration)
        return thumbCenterX(atFraction: clampedTime / duration, width: width)
    }

    private func thumbCenterX(atFraction fraction: Double, width: CGFloat) -> CGFloat {
        let inset = min(Self.thumbSize.width / 2, width / 2)
        return inset + CGFloat(fraction.clamped(to: 0...1)) * (width - inset * 2)
    }

    private func thumbClearance(in size: CGSize) -> CGRect {
        let centerX = thumbCenterX(atFraction: thumbFraction, width: size.width)
        return CGRect(
            x: centerX - Self.thumbSize.width / 2,
            y: (size.height - Self.thumbSize.height) / 2,
            width: Self.thumbSize.width,
            height: Self.thumbSize.height
        )
    }

    private func stripePath(in rect: CGRect) -> Path {
        var path = Path()

        var x = -rect.height
        while x < rect.width + rect.height {
            path.move(to: CGPoint(x: rect.minX + x, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + x + rect.height, y: rect.minY))
            x += Self.stripeSpacing
        }

        return path
    }
}

#Preview {
    Slider(value: .constant(86), in: 0...600)
        .overlay {
            NowPlayingSkipZoneRail(
                duration: 600,
                zones: [
                    PlaybackSkipZone(id: 1, startTime: 40, endTime: 65),
                    PlaybackSkipZone(id: 2, startTime: 310, endTime: 350)
                ],
                displayOnlyZones: [
                    PlaybackSkipZone(id: 3, startTime: 120, endTime: 180),
                    PlaybackSkipZone(id: 4, startTime: 470, endTime: 520)
                ],
                chapterMarkers: [90, 240, 420],
                thumbFraction: 86.0 / 600
            )
        }
        .padding()
        .tint(.accentColor)
}
