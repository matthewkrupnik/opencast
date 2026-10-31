import Foundation
import SwiftData

/// Download settings changes, each saved first and acted on after: turning
/// a show on downloads its newest episode, and a lower limit trims at once.
extension OpenCastAppModel {
    @discardableResult
    func setAutoDownloadsNewEpisodes(
        _ isEnabled: Bool,
        forPodcastID podcastID: String,
        modelContext: ModelContext
    ) -> Bool {
        guard isEnabled else {
            return downloadSettings.setAutoDownloadsNewEpisodes(
                false,
                forPodcastID: podcastID,
                modelContext: modelContext
            )
        }
        return autoDownloads.enableAutoDownload(forPodcastID: podcastID, modelContext: modelContext)
    }

    @discardableResult
    func setKeepLimitOverride(
        _ keepLimit: DownloadKeepLimit?,
        forPodcastID podcastID: String,
        modelContext: ModelContext
    ) -> Bool {
        guard downloadSettings.setKeepLimitOverride(keepLimit, forPodcastID: podcastID, modelContext: modelContext) else {
            return false
        }
        downloadCleanup.trimDownloadsToKeepLimit(forPodcastID: podcastID, modelContext: modelContext)
        return true
    }

    @discardableResult
    func setDefaultKeepLimit(_ keepLimit: DownloadKeepLimit, modelContext: ModelContext) -> Bool {
        guard downloadSettings.setDefaultKeepLimit(keepLimit, modelContext: modelContext) else {
            return false
        }
        downloadCleanup.trimAllDownloadsToKeepLimits(modelContext: modelContext)
        return true
    }

    /// Turning Wi-Fi Only off starts any downloads it was holding back.
    @discardableResult
    func setAutoDownloadsRequireWiFi(_ requiresWiFi: Bool, modelContext: ModelContext) -> Bool {
        guard downloadSettings.setAutoDownloadsRequireWiFi(requiresWiFi, modelContext: modelContext) else {
            return false
        }
        if !requiresWiFi {
            autoDownloads.schedulePass(modelContext: modelContext)
        }
        return true
    }

    @discardableResult
    func setDownloadsListGrouping(_ grouping: DownloadsListGrouping, modelContext: ModelContext) -> Bool {
        downloadSettings.setListGrouping(grouping, modelContext: modelContext)
    }

    func scheduleAutoDownloadPass(modelContext: ModelContext) {
        autoDownloads.schedulePass(modelContext: modelContext)
    }

    func runAutoDownloadPass(modelContext: ModelContext) async {
        await autoDownloads.runPass(modelContext: modelContext)
    }

    /// A new-episode push woke the app (in the background or not): refreshes
    /// that show's feed and starts its automatic downloads, which the
    /// background download session finishes after the app is suspended.
    /// Returns whether any download started; never waits for one to finish.
    func handleNewEpisodePush(feedURL: String, modelContext: ModelContext) async -> Bool {
        await ensureCoreStoresLoaded(modelContext: modelContext)
        guard library.activePodcastIDs.contains(feedURL) else {
            AutoDetectAdsLog.record("push wake ignored podcastID=\(feedURL) reason=notSubscribed")
            return false
        }
        let downloadingBefore = Set(downloads.records.filter { $0.state == .downloading }.map(\.episodeID))
        await library.refresh(feedURL: feedURL, modelContext: modelContext)
        await autoDownloads.runWakePass(modelContext: modelContext)
        let started = downloads.records.contains {
            $0.state == .downloading && !downloadingBefore.contains($0.episodeID)
        }
        AutoDetectAdsLog.record(
            "push wake podcastID=\(feedURL) autoDownload=\(downloadSettings.autoDownloadsNewEpisodes(forPodcastID: feedURL)) "
                + "downloadStarted=\(started) sceneActive=\(isSceneActive)"
        )
        return started
    }

    /// Each root scene's lifecycle reports its phase here, from its first
    /// appearance to its removal.
    func setAutoDownloadsScene(_ sceneID: UUID, isActive: Bool) {
        autoDownloads.setScene(sceneID, isActive: isActive)
    }

    func removeAutoDownloadsScene(_ sceneID: UUID) {
        autoDownloads.removeScene(sceneID)
    }

    func trimDownloadsToKeepLimits(modelContext: ModelContext) {
        downloadCleanup.trimAllDownloadsToKeepLimits(modelContext: modelContext)
    }
}
