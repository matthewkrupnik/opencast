/// What the playlist name prompt is asking for: a name for a new playlist,
/// or a new name for an existing one.
nonisolated struct PlaylistNamePromptRequest: Identifiable, Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case create
        case rename(playlistID: String)
    }

    let kind: Kind
    let initialName: String

    var id: String {
        switch kind {
        case .create:
            "create"
        case .rename(let playlistID):
            "rename-\(playlistID)"
        }
    }

    var title: String {
        switch kind {
        case .create:
            "New Playlist"
        case .rename:
            "Rename Playlist"
        }
    }

    var confirmTitle: String {
        switch kind {
        case .create:
            "Create"
        case .rename:
            "Rename"
        }
    }

    static func create() -> PlaylistNamePromptRequest {
        PlaylistNamePromptRequest(kind: .create, initialName: "")
    }

    static func rename(_ playlist: PlaylistSummary) -> PlaylistNamePromptRequest {
        PlaylistNamePromptRequest(kind: .rename(playlistID: playlist.playlistID), initialName: playlist.name)
    }
}
