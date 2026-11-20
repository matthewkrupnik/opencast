import SwiftUI

/// A quiet capsule saying the episode is streaming, so a stall reads as the
/// network rather than the app. Downloads are the normal case and show
/// nothing. Sized like `NowPlayingSourcePill` so the two can share the status
/// slot; it is a status, not a control, so its glass is not interactive.
struct NowPlayingStreamingIndicator: View {
    let origin: PlaybackMediaOrigin?

    var body: some View {
        if origin == .streaming {
            Label("Streaming", systemImage: "antenna.radiowaves.left.and.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .glassEffect(.regular, in: .capsule)
                .frame(minHeight: NowPlayingSourcePill.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Streaming from the network")
                .accessibilityIdentifier("Now Playing Streaming Indicator")
        }
    }
}
