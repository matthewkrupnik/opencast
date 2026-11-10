import Foundation
import OpenCastCore
import Testing

@Suite("Podcasting 2.0 JSON chapters")
struct PodcastChaptersDocumentTests {
    private let documentURL = URL(string: "https://cdn.example.com/shows/42/chapters.json")!

    private func chapters(_ json: String) throws -> [EpisodeChapter] {
        try PodcastChaptersDocument.chapters(from: Data(json.utf8), documentURL: documentURL)
    }

    @Test("Decodes titles, times and chapter art, sorted by start")
    func decodesChapters() throws {
        let result = try chapters("""
        {"version":"1.2.0","chapters":[
          {"startTime":312.5,"title":"Interview","img":"https://img.example.com/b.jpg","endTime":900},
          {"startTime":0,"title":" Intro ","img":"art/a.png"}
        ]}
        """)

        #expect(result == [
            EpisodeChapter(
                id: 0,
                title: "Intro",
                startTime: 0,
                imageURL: URL(string: "https://cdn.example.com/shows/42/art/a.png")
            ),
            EpisodeChapter(
                id: 1,
                title: "Interview",
                startTime: 312.5,
                endTime: 900,
                imageURL: URL(string: "https://img.example.com/b.jpg")
            ),
        ])
    }

    @Test("Keeps toc:false entries as hidden art and skips malformed ones")
    func filtersEntries() throws {
        let result = try chapters("""
        {"chapters":[
          {"startTime":0,"title":"Kept"},
          {"startTime":10,"title":"Art only","toc":false,"img":"https://img.example.com/x.jpg"},
          {"title":"No start"},
          {"startTime":-5,"title":"Negative"},
          {"startTime":"20.5","title":"String start"},
          {"startTime":30}
        ]}
        """)

        #expect(result.map(\.title) == ["Kept", "Art only", "String start", "Chapter 3"])
        #expect(result.map(\.isHidden) == [false, true, false, false])
        #expect(result.map(\.startTime) == [0, 10, 20.5, 30])
        #expect(result.map(\.id) == [0, 1, 2, 3])
    }

    @Test("Resolves chapter links like art and drops non-web ones")
    func decodesLinks() throws {
        let result = try chapters("""
        {"chapters":[
          {"startTime":0,"title":"A","url":"https://example.com/a"},
          {"startTime":1,"title":"B","url":"/b"},
          {"startTime":2,"title":"C","url":"mailto:x@example.com"}
        ]}
        """)

        #expect(result.map(\.linkURL) == [
            URL(string: "https://example.com/a"),
            URL(string: "https://cdn.example.com/b"),
            nil,
        ])
    }

    @Test("Drops non-web image URLs and end times that do not follow the start")
    func sanitizesFields() throws {
        let result = try chapters("""
        {"chapters":[
          {"startTime":5,"endTime":5,"title":"A","img":"javascript:alert(1)"},
          {"startTime":6,"title":"B","img":"   "}
        ]}
        """)

        #expect(result.map(\.imageURL) == [nil, nil])
        #expect(result.map(\.endTime) == [nil, nil])
    }

    @Test("Rejects a document that is not a chapters object")
    func rejectsInvalidDocument() {
        #expect(throws: PodcastChaptersDocument.InvalidDocumentError.self) {
            try chapters("<html>not json</html>")
        }
        #expect(throws: PodcastChaptersDocument.InvalidDocumentError.self) {
            try chapters(#"{"version":"1.2.0"}"#)
        }
    }
}
