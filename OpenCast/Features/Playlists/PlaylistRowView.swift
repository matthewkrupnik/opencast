import SwiftUI

/// A playlist in the collection: the playlist symbol in its color, and its
/// name.
struct PlaylistRowView: View {
    static let symbolName = "music.note.list"

    let summary: PlaylistSummary

    static func accessibilityIdentifier(for playlistID: String) -> String {
        "playlist-row-\(playlistID)"
    }

    var body: some View {
        NavigationLink(value: AppRoute.playlistDetail(id: summary.playlistID)) {
            Label {
                Text(summary.name)
            } icon: {
                Image(systemName: Self.symbolName)
                    .foregroundStyle(summary.tint.color)
            }
        }
        .accessibilityIdentifier(Self.accessibilityIdentifier(for: summary.playlistID))
    }
}
