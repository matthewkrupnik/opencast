import Foundation

/// Decodes a Podcasting 2.0 JSON chapters document (`application/json+chapters`),
/// the file a feed's `podcast:chapters` element points at.
public enum PodcastChaptersDocument {
    public struct InvalidDocumentError: Error, Equatable {}

    /// Chapters sorted by start time. An entry without a usable `startTime` is
    /// skipped rather than failing the document; `toc: false` entries come back
    /// hidden, since they still carry art. A relative `img` or `url` resolves
    /// against `documentURL`; only http(s) addresses are kept.
    public static func chapters(from data: Data, documentURL: URL) throws -> [EpisodeChapter] {
        guard let document = try? JSONDecoder().decode(Document.self, from: data) else {
            throw InvalidDocumentError()
        }

        let entries = document.chapters
            .compactMap(\.entry)
            .filter { $0.startTime.isFinite && $0.startTime >= 0 }
            .sorted { $0.startTime < $1.startTime }

        var visibleCount = 0
        return entries.enumerated().map { index, entry in
            let isHidden = entry.toc == false
            if !isHidden {
                visibleCount += 1
            }
            return EpisodeChapter(
                id: index,
                title: entry.title ?? "Chapter \(visibleCount)",
                startTime: entry.startTime,
                endTime: entry.endTime.flatMap { $0 > entry.startTime ? $0 : nil },
                imageURL: entry.img.flatMap { webURL($0, relativeTo: documentURL) },
                linkURL: entry.url.flatMap { webURL($0, relativeTo: documentURL) },
                isHidden: isHidden
            )
        }
    }

    private static func webURL(_ string: String, relativeTo base: URL) -> URL? {
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
        let chapters: [LenientEntry]
    }

    /// One malformed chapter must not take the rest of the document with it.
    private struct LenientEntry: Decodable {
        let entry: Entry?

        init(from decoder: any Decoder) throws {
            entry = try? Entry(from: decoder)
        }
    }

    private struct Entry: Decodable {
        let startTime: TimeInterval
        let endTime: TimeInterval?
        let title: String?
        let img: String?
        let url: String?
        let toc: Bool?

        enum CodingKeys: String, CodingKey {
            case startTime, endTime, title, img, url, toc
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            startTime = try Self.seconds(container, .startTime)
            endTime = try? Self.seconds(container, .endTime)
            let rawTitle = try? container.decodeIfPresent(String.self, forKey: .title)
            let trimmedTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            title = trimmedTitle?.isEmpty == false ? trimmedTitle : nil
            img = try? container.decodeIfPresent(String.self, forKey: .img)
            url = try? container.decodeIfPresent(String.self, forKey: .url)
            toc = try? container.decodeIfPresent(Bool.self, forKey: .toc)
        }

        /// The spec says number; some generators write a numeric string.
        private static func seconds(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> TimeInterval {
            if let number = try? container.decode(Double.self, forKey: key) {
                return number
            }
            let string = try container.decode(String.self, forKey: key)
            guard let number = Double(string.trimmingCharacters(in: .whitespaces)) else {
                throw InvalidDocumentError()
            }
            return number
        }
    }
}
