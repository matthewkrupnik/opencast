import Foundation
import OpenCastCore
import Testing
@testable import OpenCast

@MainActor
@Suite("PodcastChaptersLoader")
struct PodcastChaptersLoaderTests {
    private let url = URL(string: "https://cdn.example.com/ep1/chapters.json")!
    private let document = #"{"version":"1.2.0","chapters":[{"startTime":0,"title":"Intro","img":"intro.jpg"}]}"#
    private let directory = URL.temporaryDirectory.appending(path: "ChapterDocumentsTests-\(UUID().uuidString)")

    private func makeLoader(_ client: ScriptedChaptersHTTPClient) -> PodcastChaptersLoader {
        PodcastChaptersLoader(httpClient: client, documentDirectory: directory)
    }

    @Test("Decodes a fetched document and serves it from memory afterwards")
    func cachesDecodedDocument() async {
        let client = ScriptedChaptersHTTPClient(responses: [.success(status: 200, body: document)])
        let loader = makeLoader(client)

        let first = await loader.chapters(at: url)
        let second = await loader.chapters(at: url)

        #expect(first.map(\.title) == ["Intro"])
        #expect(first.first?.imageURL == URL(string: "https://cdn.example.com/ep1/intro.jpg"))
        #expect(second == first)
        #expect(await client.requestCount == 1)
        #expect(await client.lastAcceptHeader?.hasPrefix("application/json+chapters") == true)
    }

    @Test("A failed fetch reads as no chapters and is retried next time")
    func retriesAfterFailure() async {
        let client = ScriptedChaptersHTTPClient(responses: [
            .success(status: 404, body: "missing"),
            .failure,
            .success(status: 200, body: "not json"),
            .success(status: 200, body: document),
        ])
        let loader = makeLoader(client)

        #expect(await loader.chapters(at: url).isEmpty)
        #expect(await loader.chapters(at: url).isEmpty)
        #expect(await loader.chapters(at: url).isEmpty)
        #expect(await loader.chapters(at: url).map(\.title) == ["Intro"])
        #expect(await client.requestCount == 4)
    }

    @Test("Falls back to the saved copy when a later fetch fails")
    func readsSavedCopyOffline() async {
        let online = ScriptedChaptersHTTPClient(responses: [.success(status: 200, body: document)])
        _ = await makeLoader(online).chapters(at: url)

        let offline = ScriptedChaptersHTTPClient(responses: [.failure])
        let chapters = await makeLoader(offline).chapters(at: url)

        #expect(chapters.map(\.title) == ["Intro"])
        #expect(chapters.first?.imageURL == URL(string: "https://cdn.example.com/ep1/intro.jpg"))
        #expect(await offline.requestCount == 1)
    }

    @Test("Decodes inline chapters without a request")
    func decodesInlineDocument() async throws {
        let feed = Data(
            """
            <rss version="2.0" xmlns:psc="http://podlove.org/simple-chapters"><channel><title>S</title>
            <item><title>E</title><guid>e</guid><enclosure url="https://example.com/a.mp3" type="audio/mpeg"/>
            <psc:chapters><psc:chapter start="00:00:05" title="Inline"/></psc:chapters></item>
            </channel></rss>
            """.utf8
        )
        let snapshot = try RSSFeedParser().parse(data: feed, feedURL: URL(string: "https://example.com/feed.xml")!)
        let inlineURL = try #require(snapshot.episodes.first?.chaptersURL)
        let client = ScriptedChaptersHTTPClient(responses: [])

        let chapters = await makeLoader(client).chapters(at: inlineURL)

        #expect(chapters.map(\.title) == ["Inline"])
        #expect(chapters.map(\.startTime) == [5])
        #expect(await client.requestCount == 0)
    }

    @Test("Never fetches a non-web URL")
    func ignoresNonWebURL() async {
        let client = ScriptedChaptersHTTPClient(responses: [.success(status: 200, body: document)])
        let loader = makeLoader(client)

        #expect(await loader.chapters(at: URL(string: "file:///etc/chapters.json")!).isEmpty)
        #expect(await client.requestCount == 0)
    }
}

private actor ScriptedChaptersHTTPClient: OpenCastHTTPClient {
    enum Response {
        case success(status: Int, body: String)
        case failure
    }

    private var responses: [Response]
    private(set) var requestCount = 0
    private(set) var lastAcceptHeader: String?

    init(responses: [Response]) {
        self.responses = responses
    }

    func feedFile(for request: URLRequest, maximumBodyByteCount: Int) async throws -> OpenCastHTTPFileResult {
        throw URLError(.unsupportedURL)
    }

    func data(for request: URLRequest) async throws -> OpenCastHTTPResult {
        requestCount += 1
        lastAcceptHeader = request.value(forHTTPHeaderField: "Accept")
        guard !responses.isEmpty else {
            throw URLError(.resourceUnavailable)
        }
        switch responses.removeFirst() {
        case .failure:
            throw URLError(.notConnectedToInternet)
        case .success(let status, let body):
            return OpenCastHTTPResult(
                data: Data(body.utf8),
                response: OpenCastHTTPResponse(
                    url: request.url,
                    mimeType: "application/json",
                    expectedContentLength: Int64(body.utf8.count),
                    statusCode: status,
                    headers: [:]
                )
            )
        }
    }
}
