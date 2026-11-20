import OpenCastCore
import OpenCastPlayback
import SwiftUI

/// The bubble shown over the thumb while scrubbing: where the drag would
/// land, and what's there. Hidden from VoiceOver, since the slider's own
/// value already speaks the position.
struct NowPlayingScrubPreviewBubble: View {
    let preview: NowPlayingScrubPreview

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text(preview.time.formattedPlaybackDuration)
                    .font(.subheadline.weight(.semibold))
                if let remaining = preview.remaining {
                    Text("-\(remaining.formattedPlaybackDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()

            if let chapterTitle = preview.chapterTitle {
                Text(chapterTitle)
                    .font(.caption)
                    .lineLimit(1)
            }

            if let zone = preview.zone {
                // Red only for zones the rail draws solid red; the dimmed
                // tier stays secondary. The words carry the difference too.
                Label(zone.note, systemImage: "megaphone.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(zone == .adBreak ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    NowPlayingScrubPreviewBubble(
        preview: NowPlayingScrubPreview(
            time: 320,
            duration: 600,
            chapters: PlaybackChapterList(
                chapters: [EpisodeChapter(id: 0, title: "The interview", startTime: 240, endTime: 500)],
                source: .embedded
            ),
            zones: [PlaybackSkipZone(id: 1, startTime: 310, endTime: 350)],
            displayOnlyZones: []
        )
    )
    .padding()
}
