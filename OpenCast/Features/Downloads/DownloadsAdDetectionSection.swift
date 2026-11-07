import SwiftData
import SwiftUI

/// Always-visible Ad Detection status on the Downloads list: live per-episode
/// status for the active, pending, and finished items of the current drain,
/// plus the queue-level affordances (continue in background, resume, model
/// consent) and what to do when an item needed the listener's own key.
/// Reads the queue snapshot in its own body so per-stage queue churn
/// re-evaluates this section alone, never the downloads list around it.
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
                if let keyRequiredNotice = presentation.keyRequiredNotice {
                    Label(keyRequiredNotice, systemImage: "key")
                        .foregroundStyle(.secondary)
                }
                if let affordance = presentation.affordance {
                    affordanceRow(affordance)
                }
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
            }
        }
    }

    @ViewBuilder
    private func affordanceRow(_ affordance: AdDetectionQueuePresentation.Affordance) -> some View {
        switch affordance {
        case .continueInBackground:
            Button("Continue in Background", systemImage: "arrow.down.app", action: continueInBackground)
        case .backgroundContinuationArmed:
            Label("Continues in the background.", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .resumeInterrupted:
            Button("Resume", systemImage: "play.circle", action: resumeQueue)
        case .downloadModelConsent(let byteCount):
            Button(
                EpisodeAdFreePassPresentation.awaitingModelConsent(byteCount: byteCount).primaryActionTitle,
                systemImage: "arrow.down.circle",
                action: resumeQueue
            )
        }
    }

    private func continueInBackground() {
        appModel.armBackgroundContinuationForActiveQueue()
    }

    private func retry(_ episodeIDs: [String]) {
        appModel.retryFailedAdFreePasses(episodeIDs: episodeIDs, modelContext: modelContext)
    }

    private func resumeQueue() {
        appModel.adFreePass.resumePausedQueue()
    }
}
