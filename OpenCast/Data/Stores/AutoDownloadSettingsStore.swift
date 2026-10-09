import Foundation
import Observation
import SwiftData

/// Device-local per-show Auto-Download opt-in. Downloads live on one device,
/// so the choice does too, and it stays off the CloudKit-synced
/// `SubscriptionRecord`. A show's record value is the newest episode ID
/// already handled ("" until the first check), so a download the user
/// deletes (or a played one the sweep removes) is never fetched again.
@Observable
final class AutoDownloadSettingsStore {
    private static let keyPrefix = "autoDownload.show."

    private var handledEpisodeIDByPodcastID: [String: String] = [:]
    private(set) var lastErrorMessage: String?

    var enabledPodcastIDs: [String] {
        Array(handledEpisodeIDByPodcastID.keys)
    }

    func load(modelContext: ModelContext) {
        do {
            let records = try modelContext.fetch(
                FetchDescriptor<LocalPreferenceRecord>(
                    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                )
            )
            var loaded: [String: String] = [:]
            for record in records where record.key.hasPrefix(Self.keyPrefix) {
                let podcastID = String(record.key.dropFirst(Self.keyPrefix.count))
                guard !podcastID.isEmpty, loaded[podcastID] == nil else {
                    continue
                }
                loaded[podcastID] = record.value
            }
            handledEpisodeIDByPodcastID = loaded
            lastErrorMessage = nil
        } catch {
            handledEpisodeIDByPodcastID = [:]
            lastErrorMessage = "Unable to load auto-download settings: \(error.localizedDescription)"
        }
    }

    func isEnabled(forPodcastID podcastID: String) -> Bool {
        handledEpisodeIDByPodcastID[podcastID] != nil
    }

    func handledEpisodeID(forPodcastID podcastID: String) -> String? {
        handledEpisodeIDByPodcastID[podcastID]
    }

    @discardableResult
    func setEnabled(_ isEnabled: Bool, forPodcastID podcastID: String, modelContext: ModelContext) -> Bool {
        guard self.isEnabled(forPodcastID: podcastID) != isEnabled else {
            return true
        }

        return isEnabled
            ? write("", forPodcastID: podcastID, modelContext: modelContext)
            : removePreference(forPodcastID: podcastID, modelContext: modelContext)
    }

    @discardableResult
    func markHandled(episodeID: String, forPodcastID podcastID: String, modelContext: ModelContext) -> Bool {
        guard isEnabled(forPodcastID: podcastID),
              handledEpisodeIDByPodcastID[podcastID] != episodeID
        else {
            return true
        }

        return write(episodeID, forPodcastID: podcastID, modelContext: modelContext)
    }

    @discardableResult
    func removePreference(forPodcastID podcastID: String, modelContext: ModelContext) -> Bool {
        let previousValue = handledEpisodeIDByPodcastID.removeValue(forKey: podcastID)
        do {
            try LocalPreferenceRecord.deletePreferences(
                forKey: Self.keyPrefix + podcastID,
                modelContext: modelContext
            )
            try modelContext.save()
            lastErrorMessage = nil
            return true
        } catch {
            handledEpisodeIDByPodcastID[podcastID] = previousValue
            lastErrorMessage = "Unable to update auto-download for this show: \(error.localizedDescription)"
            return false
        }
    }

    private func write(_ value: String, forPodcastID podcastID: String, modelContext: ModelContext) -> Bool {
        let previousValue = handledEpisodeIDByPodcastID[podcastID]
        handledEpisodeIDByPodcastID[podcastID] = value
        do {
            try LocalPreferenceRecord.upsert(
                key: Self.keyPrefix + podcastID,
                value: value,
                modelContext: modelContext
            )
            try modelContext.save()
            lastErrorMessage = nil
            return true
        } catch {
            handledEpisodeIDByPodcastID[podcastID] = previousValue
            lastErrorMessage = "Unable to update auto-download for this show: \(error.localizedDescription)"
            return false
        }
    }
}
