import SwiftData
import SwiftUI

/// The playlist detail toolbar menu: Play Next, Play Last and Download All,
/// then Playlist Settings, rename and delete. The rule decides the order and
/// membership, so there is no reordering here. Deleting pops back to the collection.
struct PlaylistActionsMenu: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let summary: PlaylistSummary
    let canEnqueue: Bool
    let canDownloadAll: Bool
    let onShowSettings: () -> Void
    @State private var namePromptRequest: PlaylistNamePromptRequest?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingDownloadAll = false
    @State private var isShowingNothingToDownload = false
    @State private var downloadAllCount = 0

    var body: some View {
        Menu {
            Button(
                "Play Next",
                systemImage: "text.line.first.and.arrowtriangle.forward",
                action: enqueueNext
            )
            .disabled(!canEnqueue)

            Button(
                "Play Last",
                systemImage: "text.line.last.and.arrowtriangle.forward",
                action: enqueueLast
            )
            .disabled(!canEnqueue)

            Button("Download All", systemImage: "arrow.down.circle", action: confirmDownloadAll)
                .disabled(!canDownloadAll)

            Divider()

            Button("Playlist Settings", systemImage: "slider.horizontal.3", action: onShowSettings)
                .disabled(summary.rule == nil)

            Button("Rename", systemImage: "pencil", action: promptRename)

            Divider()

            Button("Delete Playlist", systemImage: "trash", role: .destructive, action: confirmDelete)
        } label: {
            Label("Playlist Actions", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("Playlist Actions")
        .confirmationDialog(
            "Delete \u{201C}\(summary.name)\u{201D}?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Playlist", role: .destructive, action: deletePlaylist)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its episodes stay in your library.")
        }
        .confirmationDialog(
            downloadAllTitle,
            isPresented: $isConfirmingDownloadAll,
            titleVisibility: .visible
        ) {
            Button(downloadAllConfirmTitle, action: downloadAll)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Nothing to Download", isPresented: $isShowingNothingToDownload) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Every unplayed episode in this playlist is downloaded or downloading.")
        }
        .playlistNamePrompt($namePromptRequest, onCommit: commitName(_:name:))
    }

    // Grammar agreement resolves only on the attributed localization path.
    private var downloadAllConfirmTitle: String {
        String(AttributedString(localized: "Download ^[\(downloadAllCount) Episode](inflect: true)").characters)
    }

    private var downloadAllTitle: String {
        String(AttributedString(localized: "Download ^[\(downloadAllCount) Episode](inflect: true)?").characters)
    }

    private func enqueueNext() {
        appModel.enqueuePlaylist(summary.playlistID, position: .next, modelContext: modelContext)
    }

    private func enqueueLast() {
        appModel.enqueuePlaylist(summary.playlistID, position: .last, modelContext: modelContext)
    }

    // The candidates are resolved at tap time, not in `body`: resolving them
    // checks each downloaded file on disk, so the enabled state is only a
    // record-level gate and the empty case can still race in. Taking the
    // count here also holds the title steady while the downloads commit.
    private func confirmDownloadAll() {
        let count = appModel.playlistDownloadAllCandidates(summary.playlistID).count
        guard count > 0 else {
            isShowingNothingToDownload = true
            return
        }
        downloadAllCount = count
        isConfirmingDownloadAll = true
    }

    private func downloadAll() {
        appModel.downloadAllPlaylistEpisodes(summary.playlistID, modelContext: modelContext)
    }

    private func promptRename() {
        namePromptRequest = .rename(summary)
    }

    private func commitName(_ request: PlaylistNamePromptRequest, name: String) {
        guard case .rename(let playlistID) = request.kind else {
            return
        }
        appModel.renamePlaylist(playlistID, to: name, modelContext: modelContext)
    }

    private func confirmDelete() {
        isConfirmingDelete = true
    }

    private func deletePlaylist() {
        let isDeleted = appModel.deletePlaylist(summary.playlistID, modelContext: modelContext)
        if isDeleted {
            dismiss()
        }
    }
}
