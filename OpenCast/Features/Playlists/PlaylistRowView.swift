import SwiftUI

/// A playlist in the collection: the playlist symbol and its name.
struct PlaylistRowView: View {
    static let symbolName = "music.note.list"

    let summary: PlaylistSummary

    static func accessibilityIdentifier(for playlistID: String) -> String {
        "playlist-row-\(playlistID)"
    }

    var body: some View {
        NavigationLink(value: AppRoute.playlistDetail(id: summary.playlistID)) {
            Label(summary.name, systemImage: Self.symbolName)
        }
        .accessibilityIdentifier(Self.accessibilityIdentifier(for: summary.playlistID))
    }
}
