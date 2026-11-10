import AVFoundation
import CryptoKit
import Foundation
import OpenCastCore

public enum AVAssetChapterReader {
    /// Where art embedded in chapters is written, one file per distinct image.
    public static let defaultArtworkDirectory = URL.cachesDirectory.appending(
        path: "ChapterArtwork",
        directoryHint: .isDirectory
    )

    /// Art in the chapters (an ID3 `APIC` in a `CHAP`, or an MP4 chapter
    /// image) is written under `artworkDirectory`, named by its content hash,
    /// and comes back as the chapter's file `imageURL`.
    public static func chapters(
        in asset: AVAsset,
        artworkDirectory: URL = defaultArtworkDirectory
    ) async throws -> [EpisodeChapter] {
        nonisolated(unsafe) let asset = asset
        let locales = try await asset.load(.availableChapterLocales)
        guard let locale = preferredLocale(among: locales) else {
            return []
        }

        let groups = try await asset.loadChapterMetadataGroups(
            withTitleLocale: locale,
            containingItemsWithCommonKeys: [.commonKeyTitle, .commonKeyArtwork]
        )

        var chapters: [EpisodeChapter] = []
        for group in groups {
            let start = group.timeRange.start
            guard start.isNumeric else {
                continue
            }
            let end = CMTimeRangeGetEnd(group.timeRange)
            let title = await title(of: group)
            let imageURL = await artworkData(of: group).flatMap { writeArtwork($0, in: artworkDirectory) }
            chapters.append(EpisodeChapter(
                id: chapters.count,
                title: title ?? "Chapter \(chapters.count + 1)",
                startTime: start.seconds,
                endTime: end.isNumeric && end.seconds > start.seconds ? end.seconds : nil,
                imageURL: imageURL
            ))
        }
        return chapters.sorted { $0.startTime < $1.startTime }
    }

    private static func preferredLocale(among locales: [Locale]) -> Locale? {
        guard !locales.isEmpty else {
            return nil
        }
        let preferredLanguageCodes = Locale.preferredLanguages.compactMap { Locale(identifier: $0).language.languageCode }
        for code in preferredLanguageCodes {
            if let match = locales.first(where: { $0.language.languageCode == code }) {
                return match
            }
        }
        return locales.first
    }

    private static func artworkData(of group: AVTimedMetadataGroup) async -> Data? {
        for item in group.items where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    /// Chapters often repeat one image, and an episode is read again on every
    /// load: the content hash names the file, so each image is written once.
    private static func writeArtwork(_ data: Data, in directory: URL) -> URL? {
        let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let url = directory.appending(path: name, directoryHint: .notDirectory)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func title(of group: AVTimedMetadataGroup) async -> String? {
        for item in group.items where item.commonKey == .commonKeyTitle {
            if let value = try? await item.load(.stringValue) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }
}
