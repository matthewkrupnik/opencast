import SwiftData
import SwiftUI

struct PodcastEpisodeSwipeActionsModifier: ViewModifier {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext

    let episode: EpisodeListItemSnapshot

    func body(content: Content) -> some View {
        // State reads live inside the swipe-action builders, which SwiftUI
        // evaluates on reveal — the row body never pays the record lookup or
        // the completed-download file stat (perf 21 / sync-data I).
        content
            .swipeActions(edge: .leading) {
                let isPlayed = appModel.library.progressRecord(for: episode.episodeID)?.isPlayed == true
                Button(
                    isPlayed ? "Mark Unplayed" : "Mark Played",
                    systemImage: isPlayed ? "arrow.uturn.backward.circle" : "checkmark.circle",
                    action: togglePlayed
                )
                .tint(isPlayed ? .blue : .green)
            }
            // A swipe action draws a disabled button exactly like an enabled
            // one, so an action that cannot run is left out, never disabled:
            // the row's context menu keeps the greyed item.
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                let downloadState = appModel.downloadMenuState(for: episode)
                if downloadState.showsDownloadAction {
                    Button("Download", systemImage: "arrow.down.circle", action: download)
                        .tint(.blue)
                }
            }
    }

    private func togglePlayed() {
        appModel.toggleEpisodePlayed(episode, modelContext: modelContext)
    }

    private func download() {
        appModel.downloads.startDownload(for: episode, modelContext: modelContext)
    }
}
