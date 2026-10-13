nonisolated struct CarPlayPlaylistRow: Identifiable, Equatable, Sendable {
    let playlistID: String
    let title: String
    let detailText: String?
    /// The playlist's most dominant matched show's artwork.
    let artworkURL: String?
    /// The playlist's symbol, when it has no cover artwork.
    let symbolName: String?

    var id: String {
        playlistID
    }
}
