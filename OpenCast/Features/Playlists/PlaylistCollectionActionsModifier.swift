import SwiftData
import SwiftUI

/// Play, Rename and Delete for a playlist row in the collection, as swipes
/// and a context menu.
struct PlaylistCollectionActionsModifier: ViewModifier {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @State private var isConfirmingDelete = false

    let summary: PlaylistSummary
    let onRename: (PlaylistSummary) -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading) {
                Button("Play", systemImage: "play.fill", action: play)
                    .tint(.accentColor)
            }
            // A destructive role would animate the row away before the
            // confirmation answers, so Delete is only tinted red.
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash", action: confirmDelete)
                    .tint(.red)
                Button("Rename", systemImage: "pencil", action: rename)
            }
            .contextMenu {
                Button("Play", systemImage: "play.fill", action: play)
                Divider()
                Button("Rename", systemImage: "pencil", action: rename)
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive, action: confirmDelete)
            }
            .confirmationDialog(
                "Delete “\(summary.name)”?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Playlist", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its episodes stay in your library.")
            }
    }

    private func play() {
        appModel.playPlaylist(summary.playlistID, modelContext: modelContext)
    }

    private func rename() {
        onRename(summary)
    }

    private func confirmDelete() {
        isConfirmingDelete = true
    }

    private func delete() {
        appModel.deletePlaylist(summary.playlistID, modelContext: modelContext)
    }
}
