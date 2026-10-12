import CryptoKit
import Foundation
import OSLog
import UIKit
import UserNotifications

/// Posts local new-episode notifications in the same shape the push server
/// used, so tap routing and the rich content extension work unchanged.
/// Episodes found while the app is active are recorded but not posted.
struct NewEpisodeNotificationScheduler {
    static let requestIdentifierPrefix = "opencast-episode-"
    static let summaryThreshold = 3

    private static let logger = Logger(subsystem: "mk.lan.opencast", category: "NewEpisodeNotifications")

    var center: any AdFreePassNotificationCenter = UNUserNotificationCenter.current()
    var artwork: @Sendable (URL) async -> UIImage? = { url in
        try? await ArtworkLoader.shared.image(for: ArtworkRequest(url: url, targetPixelSize: CGSize(width: 600, height: 600)))
    }

    func post(_ candidates: [NewEpisodeCandidate], isSceneActive: Bool) async {
        guard !candidates.isEmpty,
              !isSceneActive,
              AdFreePassCompletionNotificationScheduler.allowsLocalDelivery(await center.authorizationStatus())
        else {
            return
        }
        let requests: [UNNotificationRequest]
        if candidates.count > Self.summaryThreshold {
            requests = [Self.summaryRequest(candidates)]
        } else {
            var built: [UNNotificationRequest] = []
            for candidate in candidates {
                let content = Self.content(for: candidate)
                content.attachments = await attachments(for: candidate)
                built.append(UNNotificationRequest(
                    identifier: Self.requestIdentifierPrefix + candidate.episodeID,
                    content: content,
                    trigger: nil
                ))
            }
            requests = built
        }
        for request in requests {
            do {
                try await center.add(request)
            } catch {
                Self.logger.error("new-episode notification add failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func content(for candidate: NewEpisodeCandidate) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = candidate.podcastTitle
        content.subtitle = candidate.title
        let summary = plainSummary(candidate.summary)
        content.body = summary
        content.sound = .default
        content.categoryIdentifier = OpenCastNotificationCategory.episode
        content.threadIdentifier = threadIdentifier(feedURL: candidate.feedURL)
        content.targetContentIdentifier = candidate.episodeID
        var payload: [String: Any] = [
            "kind": "episode",
            "feed_url": candidate.feedURL,
            "episode_id": candidate.episodeID,
            "episode_title": candidate.title,
            "podcast_title": candidate.podcastTitle,
            "episode_summary": summary
        ]
        if let duration = candidate.duration, duration > 0 {
            payload["episode_duration_text"] = "\(Int((duration / 60).rounded())) MIN"
        }
        content.userInfo = ["opencast": payload]
        return content
    }

    static func summaryRequest(_ candidates: [NewEpisodeCandidate]) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "\(candidates.count) new episodes"
        var shows: [String] = []
        for candidate in candidates where !shows.contains(candidate.podcastTitle) {
            shows.append(candidate.podcastTitle)
        }
        content.body = shows.prefix(3).joined(separator: ", ") + (shows.count > 3 ? ", and more" : "")
        content.sound = .default
        content.threadIdentifier = "opencast-episodes-summary"
        // The delegate's router only acts on "episode"; this opens the app.
        content.userInfo = ["opencast": ["kind": "episode-summary"]]
        return UNNotificationRequest(identifier: "opencast-episodes-summary", content: content, trigger: nil)
    }

    static func threadIdentifier(feedURL: String) -> String {
        let digest = SHA256.hash(data: Data(feedURL.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "opencast-episodes-\(digest)"
    }

    /// Show notes are HTML; the notification gets a short plain-text line.
    static func plainSummary(_ html: String?) -> String {
        guard let html, !html.isEmpty else {
            return ""
        }
        let withoutTags = html.replacing(/<[^>]+>/, with: " ")
        let decoded = withoutTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        let collapsed = decoded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 180 ? String(collapsed.prefix(179)) + "…" : collapsed
    }

    private func attachments(for candidate: NewEpisodeCandidate) async -> [UNNotificationAttachment] {
        var result: [UNNotificationAttachment] = []
        let pairs: [(String, URL?)] = [
            (NotificationArtworkAttachmentIdentifier.podcast, candidate.podcastArtworkURL),
            (NotificationArtworkAttachmentIdentifier.episode, candidate.episodeArtworkURL)
        ]
        for (identifier, url) in pairs {
            guard let url, url != candidate.podcastArtworkURL || identifier == NotificationArtworkAttachmentIdentifier.podcast,
                  let image = await withTimeout(seconds: 3, { await artwork(url) }),
                  let data = image.jpegData(compressionQuality: 0.85)
            else {
                continue
            }
            // UNNotificationAttachment takes ownership of its file.
            let fileURL = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
                .appending(path: "artwork.jpg")
            do {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: fileURL)
                result.append(try UNNotificationAttachment(identifier: identifier, url: fileURL))
            } catch {
                continue
            }
        }
        return result
    }

    private func withTimeout<T: Sendable>(seconds: TimeInterval, _ operation: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
