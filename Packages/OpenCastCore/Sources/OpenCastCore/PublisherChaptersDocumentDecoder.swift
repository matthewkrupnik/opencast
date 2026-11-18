import Foundation

public enum PublisherChaptersDocumentDecoder {
    public static let maximumChapterCount = 1_000
    public static let maximumTitleLength = 200
    /// About 31 years: far past any episode, and far below where the `Duration`
    /// and `CMTime` conversions of a timestamp stop being exact (or trap).
    public static let maximumTimestamp: TimeInterval = 1_000_000_000

    /// Podcasting 2.0 JSON chapters (jsonChapters 1.2) → display chapters, sorted by start, ids positional.
    ///
    /// Strict on the root, lenient inside it: entries without a usable start or title and entries
    /// starting past `maximumTimestamp` are dropped rather than failing the document. An end past
    /// `maximumTimestamp` reads as absent. A time may be a number or a numeric string. `toc: false`
    /// entries come back hidden when they carry art, which they still change, and are dropped
    /// otherwise. A relative `img` or `url` resolves against `documentURL`; only http(s)
    /// addresses are kept.
    public static func decode(_ data: Data, documentURL: URL? = nil) throws -> [EpisodeChapter] {
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw PublisherChaptersDocumentError.invalidJSON
        }
        guard let entries = document.chapters else {
            throw PublisherChaptersDocumentError.malformedRoot
        }

        let candidates = entries.enumerated()
            .compactMap { offset, entry in entry.entry.map { (offset: offset, entry: $0) } }
            .sorted { ($0.entry.startTime, $0.offset) < ($1.entry.startTime, $1.offset) }
            .map(\.entry)

        var chapters: [EpisodeChapter] = []
        var lastListedStart: TimeInterval?
        for candidate in candidates {
            guard chapters.count < maximumChapterCount else { break }
            let isHidden = candidate.toc == false
            let imageURL = candidate.img.flatMap { webURL($0, relativeTo: documentURL) }
            if isHidden {
                // A hidden entry only changes the art.
                guard imageURL != nil else { continue }
            } else {
                // Two listed chapters at one start would bounce between themselves.
                guard candidate.title != nil, lastListedStart != candidate.startTime else { continue }
                lastListedStart = candidate.startTime
            }
            chapters.append(EpisodeChapter(
                id: chapters.count,
                title: candidate.title ?? "",
                startTime: candidate.startTime,
                endTime: candidate.endTime,
                imageURL: imageURL,
                linkURL: candidate.url.flatMap { webURL($0, relativeTo: documentURL) },
                isHidden: isHidden
            ))
        }
        return chapters
    }

    private static func webURL(_ string: String, relativeTo base: URL?) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else {
            return nil
        }
        return url
    }

    private struct Document: Decodable {
        let chapters: [LenientEntry]?

        init(from decoder: any Decoder) {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            chapters = try? container?.decode([LenientEntry].self, forKey: .chapters)
        }

        private enum CodingKeys: String, CodingKey {
            case chapters
        }
    }

    /// One malformed chapter must not take the rest of the document with it.
    private struct LenientEntry: Decodable {
        let entry: Entry?

        init(from decoder: any Decoder) {
            entry = Entry(in: try? decoder.container(keyedBy: Entry.CodingKeys.self))
        }
    }

    private struct Entry {
        let startTime: TimeInterval
        let endTime: TimeInterval?
        let title: String?
        let img: String?
        let url: String?
        let toc: Bool?

        enum CodingKeys: String, CodingKey {
            case startTime, endTime, title, img, url, toc
        }

        init?(in container: KeyedDecodingContainer<CodingKeys>?) {
            guard let container,
                  let startTime = Self.seconds(container, .startTime),
                  (0...PublisherChaptersDocumentDecoder.maximumTimestamp).contains(startTime)
            else {
                return nil
            }
            self.startTime = startTime
            endTime = Self.seconds(container, .endTime)
                .flatMap { $0 > startTime && $0 <= PublisherChaptersDocumentDecoder.maximumTimestamp ? $0 : nil }
            let trimmedTitle = (try? container.decodeIfPresent(String.self, forKey: .title))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            title = trimmedTitle.flatMap { $0.isEmpty ? nil : String($0.prefix(PublisherChaptersDocumentDecoder.maximumTitleLength)) }
            img = try? container.decodeIfPresent(String.self, forKey: .img)
            url = try? container.decodeIfPresent(String.self, forKey: .url)
            toc = try? container.decodeIfPresent(Bool.self, forKey: .toc)
        }

        /// The spec says number; some generators write a numeric string.
        private static func seconds(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> TimeInterval? {
            if let number = try? container.decode(Double.self, forKey: key) {
                return number.isFinite ? number : nil
            }
            guard let string = try? container.decode(String.self, forKey: key),
                  let number = Double(string.trimmingCharacters(in: .whitespaces)),
                  number.isFinite
            else {
                return nil
            }
            return number
        }
    }
}
