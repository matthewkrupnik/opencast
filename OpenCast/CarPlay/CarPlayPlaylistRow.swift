nonisolated struct CarPlayPlaylistRow: Identifiable, Equatable, Sendable {
    let playlistID: String
    let title: String
    let detailText: String?
    /// The playlist's color, drawn as the same cover the phone shows.
    let tint: PlaylistTint

    var id: String {
        playlistID
    }
}
