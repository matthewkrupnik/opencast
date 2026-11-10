import Foundation
import OpenCastCore
import Testing

@Suite("Podlove Simple Chapters")
struct PodloveChaptersParsingTests {
    private let feedURL = URL(string: "https://example.com/feeds/show.xml")!

    private func parse(_ items: String, namespace: String = #"xmlns:psc="http://podlove.org/simple-chapters""#) throws -> FeedSnapshot {
        try RSSFeedParser().parse(
            data: Data(
                """
                <?xml version="1.0" encoding="utf-8"?>
                <rss version="2.0" \(namespace) xmlns:podcast="https://podcastindex.org/namespace/1.0">
                  <channel>
                    <title>Podlove Show</title>
                    \(items)
                  </channel>
                </rss>
                """.utf8
            ),
            feedURL: feedURL
        )
    }

    private func chapters(of episode: Episode) throws -> [EpisodeChapter] {
        let url = try #require(episode.chaptersURL)
        let data = try #require(InlineChaptersDocument.data(from: url))
        return try PodcastChaptersDocument.chapters(from: data, documentURL: url)
    }

    @Test("Inline chapters become a chapters document with times, links and art")
    func parsesInlineChapters() throws {
        let snapshot = try parse(
            """
            <item>
              <title>Episode</title>
              <guid>ep-1</guid>
              <enclosure url="https://example.com/a.mp3" type="audio/mpeg" />
              <psc:chapters version="1.2">
                <psc:chapter start="00:00:00" title="Welcome" />
                <psc:chapter start="01:30.5" title="News" href="https://example.com/news" image="art/news.jpg" />
                <psc:chapter start="1:02:03.250" title="Outro" />
                <psc:chapter title="No start" />
              </psc:chapters>
            </item>
            """
        )

        let result = try chapters(of: snapshot.episodes[0])
        #expect(result.map(\.title) == ["Welcome", "News", "Outro"])
        #expect(result.map(\.startTime) == [0, 90.5, 3_723.25])
        #expect(result[1].linkURL == URL(string: "https://example.com/news"))
        #expect(result[1].imageURL == URL(string: "https://example.com/feeds/art/news.jpg"))
    }

    @Test("A podcast:chapters link wins over inline chapters")
    func podcastChaptersWin() throws {
        let snapshot = try parse(
            """
            <item>
              <title>Episode</title>
              <guid>ep-1</guid>
              <enclosure url="https://example.com/a.mp3" type="audio/mpeg" />
              <podcast:chapters url="https://example.com/c.json" type="application/json+chapters" />
              <psc:chapters><psc:chapter start="0" title="Inline" /></psc:chapters>
            </item>
            """
        )

        #expect(snapshot.episodes[0].chaptersURL == URL(string: "https://example.com/c.json"))
    }

    @Test("Ignores chapter elements outside the Podlove namespace")
    func ignoresForeignNamespace() throws {
        let snapshot = try parse(
            """
            <item>
              <title>Episode</title>
              <guid>ep-1</guid>
              <enclosure url="https://example.com/a.mp3" type="audio/mpeg" />
              <psc:chapters><psc:chapter start="0" title="Not Podlove" /></psc:chapters>
            </item>
            """,
            namespace: #"xmlns:psc="https://example.com/other""#
        )

        #expect(snapshot.episodes[0].chaptersURL == nil)
    }

    @Test("Only inline chapters documents decode as inline data")
    func inlineDataOnlyForInlineDocuments() {
        #expect(InlineChaptersDocument.data(from: URL(string: "https://example.com/c.json")!) == nil)
        #expect(InlineChaptersDocument.data(from: URL(string: "data:text/plain;base64,aGk=")!) == nil)
    }
}
