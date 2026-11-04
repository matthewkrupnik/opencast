import SwiftUI

/// Always-visible Ad Detection status on the Downloads list. Reads the queue
/// snapshot in its own body so per-stage queue churn re-evaluates this
/// section alone, never the downloads list around it.
struct DownloadsAdDetectionSection: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let presentation = AdDetectionQueuePresentation(
            snapshot: appModel.adFreePass.queueSnapshot,
            isBackgroundSessionArmed: appModel.adFreePassBackgroundSession.isArmed
        )

        Section("Ad Detection") {
            if presentation.isEmpty {
                Text("No ad detection in progress.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(presentation.rows) { row in
                    AdDetectionQueueRowView(row: row)
                }
                ForEach(presentation.finishedRows) { row in
                    AdDetectionQueueRowView(row: row) {
                        retry([row.episodeID])
                    }
                }
                if presentation.retryableEpisodeIDs.count > 1 {
                    Button("Retry Failed", systemImage: "arrow.clockwise") {
                        retry(presentation.retryableEpisodeIDs)
                    }
                }
                NavigationLink(value: AppRoute.adDetectionQueue) {
                    Text("Show Queue")
                }
            }
        }
    }

    private func retry(_ episodeIDs: [String]) {
        appModel.retryFailedAdFreePasses(episodeIDs: episodeIDs, modelContext: modelContext)
    }
}
