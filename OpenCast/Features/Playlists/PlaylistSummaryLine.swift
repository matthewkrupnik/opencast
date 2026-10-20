import SwiftUI

/// A collection row's or tile's size line. A playlist reads its evaluation
/// here and nowhere else in the collection, so only visible rows and tiles
/// evaluate, and the collection's body observes no evaluation dependencies.
/// Callers set the font, style and line limit.
struct PlaylistSummaryLine: View {
    @Environment(OpenCastAppModel.self) private var appModel

    let summary: PlaylistSummary

    var body: some View {
        // Playlists publish before the library and downloads they evaluate
        // over; a blank line holds the row's height instead of "No episodes".
        if appModel.coreStoresHydrated {
            line
        } else {
            Text(verbatim: " ")
        }
    }

    private var line: some View {
        let evaluation = appModel.smartPlaylistEvaluation(for: summary)
        return Text(PlaylistSummaryText.line(itemCount: evaluation.count, totalDuration: evaluation.totalDuration))
            .accessibilityLabel(
                PlaylistSummaryText.spokenLine(itemCount: evaluation.count, totalDuration: evaluation.totalDuration)
            )
    }
}
