import CryptoKit
import Foundation
import OpenCastCore

/// Fetches the JSON chapters documents feeds declare with `podcast:chapters`,
/// and decodes inline (Podlove) ones carried as data URLs without a fetch.
/// A decoded document is kept for the session and its bytes on disk, which a
/// failed fetch (offline, say) falls back to; a failure with nothing saved is
/// not remembered, so the next request tries again. Failures read as no
/// chapters (fail-open).
final class PodcastChaptersLoader {
    static let maximumDocumentByteCount = 1_024 * 1_024
    static let defaultDocumentDirectory = URL.cachesDirectory.appending(
        path: "ChapterDocuments",
        directoryHint: .isDirectory
    )

    private let httpClient: any OpenCastHTTPClient
    private let documentDirectory: URL
    private var documents: [URL: [EpisodeChapter]] = [:]
    private var inFlight: [URL: Task<[EpisodeChapter]?, Never>] = [:]

    init(httpClient: any OpenCastHTTPClient, documentDirectory: URL = defaultDocumentDirectory) {
        self.httpClient = httpClient
        self.documentDirectory = documentDirectory
    }

    func chapters(at url: URL) async -> [EpisodeChapter] {
        if let cached = documents[url] {
            return cached
        }
        let task = inFlight[url] ?? Task { [httpClient, documentDirectory] in
            await Self.fetch(url, httpClient: httpClient, documentDirectory: documentDirectory)
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result {
            documents[url] = result
        }
        return result ?? []
    }

    private nonisolated static func fetch(
        _ url: URL,
        httpClient: any OpenCastHTTPClient,
        documentDirectory: URL
    ) async -> [EpisodeChapter]? {
        if let inline = InlineChaptersDocument.data(from: url) {
            return (try? PodcastChaptersDocument.chapters(from: inline, documentURL: url)) ?? []
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        let savedURL = documentDirectory.appending(path: savedName(for: url), directoryHint: .notDirectory)
        var request = URLRequest(url: url)
        request.setValue("application/json+chapters, application/json;q=0.9, */*;q=0.1", forHTTPHeaderField: "Accept")
        if let result = try? await httpClient.data(for: request, maximumBodyByteCount: maximumDocumentByteCount),
           (200..<300).contains(result.response.statusCode ?? 200),
           let chapters = try? PodcastChaptersDocument.chapters(from: result.data, documentURL: result.response.url ?? url) {
            try? FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)
            try? result.data.write(to: savedURL, options: .atomic)
            return chapters
        }
        guard let saved = try? Data(contentsOf: savedURL) else {
            return nil
        }
        // Relative art in a saved copy resolves against the declared URL.
        return try? PodcastChaptersDocument.chapters(from: saved, documentURL: url)
    }

    private nonisolated static func savedName(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
    }
}
