import Foundation
import SwiftData

extension OpenCastAppModel {
    static let legacyAutoDownloadKeyPrefix = "autoDownload.show."

    /// Carries the fork's earlier per-show Auto-Download opt-ins
    /// (`autoDownload.show.<feed>`, valued with the newest episode ID already
    /// handled) over to `DownloadSettingsStore`, then deletes them. The
    /// watermark is that episode's release date, so nothing already handled
    /// downloads again; a show never checked yet starts from now. Runs after
    /// the library loads; rows it could not carry over stay for next launch.
    func migrateLegacyAutoDownloadPreferences(modelContext: ModelContext) {
        let prefix = Self.legacyAutoDownloadKeyPrefix
        guard let records = try? modelContext.fetch(FetchDescriptor<LocalPreferenceRecord>())
            .filter({ $0.key.hasPrefix(prefix) }),
            !records.isEmpty
        else {
            return
        }

        for record in records {
            let podcastID = String(record.key.dropFirst(prefix.count))
            if !podcastID.isEmpty, library.isActivelySubscribed(to: podcastID) {
                let watermark = library.episode(with: record.value)?.publishedAt ?? .now
                guard downloadSettings.setAutoDownloadsNewEpisodes(
                    true,
                    forPodcastID: podcastID,
                    watermark: watermark,
                    modelContext: modelContext
                ) else {
                    continue
                }
            }
            modelContext.delete(record)
        }
        try? modelContext.save()
    }
}
