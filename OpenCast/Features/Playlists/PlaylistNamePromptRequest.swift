/// What the playlist rename prompt is asking for: a new name for an
/// existing playlist.
nonisolated struct PlaylistNamePromptRequest: Identifiable, Equatable, Sendable {
    let playlistID: String
    let initialName: String

    var id: String {
        "rename-\(playlistID)"
    }

    static func rename(_ playlist: PlaylistSummary) -> PlaylistNamePromptRequest {
        PlaylistNamePromptRequest(playlistID: playlist.playlistID, initialName: playlist.name)
    }
}
