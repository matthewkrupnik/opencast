import SwiftUI

struct MiniPlayerMetadataView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let podcastTitle: String
    var playlistSource: PlaylistPlaybackSource? = nil
    var playlistRemainingCount = 0
    /// Off in the dense row: the title alone, on one line. The caller keeps
    /// the second line's text in its accessibility value.
    var showsSecondaryLine = true

    var body: some View {
        Group {
            if !showsSecondaryLine {
                Text(title)
                    .font(dynamicTypeSize.isAccessibilitySize ? .caption : .subheadline)
                    .foregroundStyle(.primary)
            } else if dynamicTypeSize.isAccessibilitySize {
                // The system accessory has a fixed height. A scaled single
                // line stays readable; VoiceOver receives both full titles.
                Text("\(title), \(podcastTitle)")
                    .font(.caption)
                    .foregroundStyle(.primary)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    secondaryLine
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var secondaryLine: some View {
        if playlistSource != nil {
            // The show stays the subject; Now Playing names the playlist. The
            // count keeps layout priority so a long show name truncates
            // before "N left" does.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(podcastTitle)
                if playlistRemainingCount >= 1 {
                    Text(PlaylistPlaybackSourceText.miniPlayerRemainingSegment(remainingCount: playlistRemainingCount))
                        .layoutPriority(1)
                }
            }
        } else {
            Text(podcastTitle)
        }
    }
}
