import Foundation
import Testing
@testable import OpenCast

@MainActor
@Suite("Episode share context")
struct EpisodeShareContextTests {
    @Test("Shares the episode's web audio URL with its title and artwork")
    func sharesAudioURL() throws {
        let context = try #require(EpisodeShareContext.make(episode: snapshot()))

        #expect(context.url == URL(string: "https://almanac.example.com/media/010-rubber-duck-final-witness.mp3"))
        #expect(context.title == "Rubber Duck, Final Witness")
        #expect(context.artworkURL == URL(string: "https://almanac.example.com/artwork/cover-v2.png"))
    }

    @Test("Falls back to the feed URL when the episode has no web audio URL")
    func fallsBackToFeedURL() throws {
        for audioURL in [nil, "", "file:///var/mobile/Downloads/episode.mp3", "not a url"] {
            let context = try #require(EpisodeShareContext.make(episode: snapshot(audioURL: audioURL)))
            #expect(context.url == URL(string: "https://almanac.example.com/feed.xml"))
        }
    }

    @Test("No context when neither the audio nor the feed URL is a web URL")
    func unshareableEpisodes() {
        #expect(EpisodeShareContext.make(episode: snapshot(audioURL: nil, podcastID: "local-import-1")) == nil)
        #expect(EpisodeShareContext.make(
            episode: snapshot(audioURL: "file:///episode.mp3", podcastID: "file:///feed.xml")
        ) == nil)
    }

    @Test("A blank episode title falls back to the show title")
    func blankTitleUsesShowTitle() throws {
        let context = try #require(EpisodeShareContext.make(episode: snapshot(title: " \n ")))

        #expect(context.title == "The Example Almanac")
    }

    private func snapshot(
        title: String = "Rubber Duck, Final Witness",
        audioURL: String? = "https://almanac.example.com/media/010-rubber-duck-final-witness.mp3",
        podcastID: String = "https://almanac.example.com/feed.xml"
    ) -> EpisodeListItemSnapshot {
        EpisodeListItemSnapshot(
            episodeID: "episode-010",
            podcastID: podcastID,
            podcastTitle: "The Example Almanac",
            title: title,
            summary: nil,
            publishedAt: Date(timeIntervalSince1970: 1_778_590_800),
            duration: 4_000,
            audioURL: audioURL,
            artworkURL: "https://almanac.example.com/artwork/cover-v2.png",
            artworkPreview: nil,
            guid: "tag:example.com,2026:almanac:010-rubber-duck-final-witness",
            cachedAt: Date(timeIntervalSince1970: 1_778_600_000)
        )
    }
}
