import AppIntents
import Foundation

@AppEntity(schema: .audio.playlist)
struct OpenCastPlaylistEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Playlist" }
    static let defaultQuery = OpenCastPlaylistQuery()

    let id: String
    var title: String
    // Required by the audio.playlist schema: every playlist is the listener's own.
    var owner: OpenCastPlaylistOwner.Owner?
    var createdByMe: Bool?
    var curatedForMe: Bool?
    var episodeCount: Int
    var episodeCountText: String
    var updatedAt: Date

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(episodeCountText)",
            image: .init(systemName: "music.note.list")
        )
    }

    @MainActor
    init(summary: PlaylistSummary, episodeCount: Int) {
        id = summary.playlistID
        self.episodeCount = episodeCount
        episodeCountText = PlaylistSummaryText.line(itemCount: episodeCount, totalDuration: 0)
        updatedAt = summary.updatedAt
        // The schema's properties are macro-wrapped: set them after the plain ones.
        title = String(summary.name.prefix(512))
        owner = nil
        createdByMe = true
        curatedForMe = false
    }

    /// Every playlist as an entity, most recently updated first (the store's
    /// array follows the collection's sort preference, so the order is made
    /// here), ties by id.
    @MainActor
    static func entities(
        for summaries: [PlaylistSummary],
        episodeCount: (PlaylistSummary) -> Int
    ) -> [OpenCastPlaylistEntity] {
        summaries.map { OpenCastPlaylistEntity(summary: $0, episodeCount: episodeCount($0)) }
            .sorted { ($0.updatedAt, $1.id) > ($1.updatedAt, $0.id) }
    }
}

// The audio.playlist schema wants `owner` as a union of Person or String.
// Same nonisolated namespace workaround as `OpenCastAudioItem`.
nonisolated enum OpenCastPlaylistOwner {
    @UnionValue
    enum Owner {
        case name(String)

        static var typeDisplayRepresentation: TypeDisplayRepresentation { "Owner" }
        static let caseDisplayRepresentations: [Cases: DisplayRepresentation] = [.name: "Name"]
    }
}
