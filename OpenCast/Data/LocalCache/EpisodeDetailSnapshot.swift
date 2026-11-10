import Foundation

nonisolated struct EpisodeDetailSnapshot: Identifiable, Equatable, Sendable {
    var listItem: EpisodeListItemSnapshot
    let showNotesHTML: String?
    /// Feed-declared chapters: a `podcast:chapters` URL, or inline Podlove
    /// chapters as a data URL; detail-only like show notes. Presence
    /// suppresses generated chapters (creator metadata wins).
    var chaptersURL: String?

    var id: String {
        listItem.episodeID
    }

    init(
        listItem: EpisodeListItemSnapshot,
        showNotesHTML: String?,
        chaptersURL: String? = nil
    ) {
        self.listItem = listItem
        self.showNotesHTML = showNotesHTML
        self.chaptersURL = chaptersURL
    }
}
