import SwiftData
import SwiftUI

/// The last week of listening on this device, newest first, each row able to
/// put its episode back where that listening started.
struct ListeningHistoryView: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext

    @State private var restoredEntryIDs: Set<String> = []

    var body: some View {
        Group {
            if appModel.listeningHistory.entries.isEmpty {
                ContentUnavailableView(
                    "No Listening History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Episodes you play or mark played on this device show up here for a week.")
                )
            } else {
                List(appModel.listeningHistory.entries) { entry in
                    row(for: entry)
                }
            }
        }
        .settingsSubscreen(title: "Listening History")
    }

    private func row(for entry: ListeningHistoryEntry) -> some View {
        let episode = appModel.episodeSnapshot(for: entry.episodeID)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(episode?.title ?? "Unavailable Episode")
                    .font(.subheadline)
                    .lineLimit(2)
                if let podcastTitle = episode?.podcastTitle {
                    Text(podcastTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(Self.summary(for: entry)) · \(entry.endedAt, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if restoredEntryIDs.contains(entry.id) {
                Label("Restored", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Restored")
            } else if !entry.isOpen {
                Button("Restore") {
                    if appModel.restoreListeningHistoryEntry(entry, modelContext: modelContext) {
                        restoredEntryIDs.insert(entry.id)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(episode == nil)
                .accessibilityHint("Puts this episode back to \(Self.timeText(entry.startPosition))")
            }
        }
        .padding(.vertical, 3)
    }

    static func summary(for entry: ListeningHistoryEntry) -> String {
        switch entry.kind {
        case .markedPlayed:
            "Marked played at \(timeText(entry.startPosition))"
        case .session:
            "\(timeText(entry.startPosition)) → \(entry.didFinish ? "end" : timeText(entry.endPosition))"
        }
    }

    static func timeText(_ position: TimeInterval) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = position >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(max(position, 0)).formatted(.time(pattern: pattern))
    }
}
