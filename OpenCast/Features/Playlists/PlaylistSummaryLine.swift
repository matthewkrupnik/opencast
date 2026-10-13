import SwiftUI

/// A collection row's or tile's size line. A playlist reads its evaluation
/// here and nowhere else in the collection, so only visible rows and tiles
/// evaluate, and the collection's body observes no evaluation dependencies.
/// Callers set the font, style and line limit.
struct PlaylistSummaryLine: View {
    @Environment(OpenCastAppModel.self) private var appModel

    let summary: PlaylistSummary

    var body: some View {
        let evaluation = appModel.smartPlaylistEvaluation(for: summary)
        Text(PlaylistSummaryText.line(itemCount: evaluation.count, totalDuration: evaluation.totalDuration))
            .accessibilityLabel(
                PlaylistSummaryText.spokenLine(itemCount: evaluation.count, totalDuration: evaluation.totalDuration)
            )
    }
}
