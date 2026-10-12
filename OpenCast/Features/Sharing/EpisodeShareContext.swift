import Foundation

/// What the Share menu offers for one episode: the episode's audio link, or
/// the show's feed link when the episode has none. Built from the cached
/// snapshot, never the playback item, whose audio URL becomes the local file
/// once the episode is downloaded.
struct EpisodeShareContext: Equatable {
    let title: String
    let artworkURL: URL?
    let url: URL

    static func make(episode: EpisodeListItemSnapshot) -> EpisodeShareContext? {
        guard let url = webURL(episode.audioURL) ?? webURL(episode.podcastID) else {
            return nil
        }
        let episodeTitle = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return EpisodeShareContext(
            title: episodeTitle.isEmpty ? episode.podcastTitle : episodeTitle,
            artworkURL: episode.artworkURL.flatMap(URL.init(string:)),
            url: url
        )
    }

    private static func webURL(_ string: String?) -> URL? {
        guard let string,
              let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host() != nil
        else {
            return nil
        }
        return url
    }
}
