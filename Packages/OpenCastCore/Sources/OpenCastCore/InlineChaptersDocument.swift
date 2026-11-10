import Foundation

/// Chapters a feed writes inline (Podlove Simple Chapters, `psc:chapter`),
/// carried as a Podcasting 2.0 JSON chapters document in a `data:` URL. It
/// travels and is stored in the same slot as a `podcast:chapters` link, so
/// every reader of that slot handles both.
public enum InlineChaptersDocument {
    static let maximumChapterCount = 1_000
    private static let prefix = "data:application/json+chapters;base64,"

    struct Chapter: Codable, Equatable {
        var startTime: TimeInterval
        var title: String?
        var url: String?
        var img: String?
    }

    private struct Document: Codable {
        var version = "1.2.0"
        var chapters: [Chapter]
    }

    static func url(for chapters: [Chapter]) -> URL? {
        guard !chapters.isEmpty, let data = try? JSONEncoder().encode(Document(chapters: chapters)) else {
            return nil
        }
        return URL(string: prefix + data.base64EncodedString())
    }

    /// The document bytes when `url` is an inline chapters document.
    public static func data(from url: URL) -> Data? {
        let string = url.absoluteString
        guard string.hasPrefix(prefix) else {
            return nil
        }
        return Data(base64Encoded: String(string.dropFirst(prefix.count)))
    }
}
