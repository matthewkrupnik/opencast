import Foundation
import Observation
import SwiftData
import UserNotifications

/// New-episode notifications, produced on device: a periodic background
/// feed check posts local notifications for newly published episodes. The
/// toggle needs notification permission and schedules that check.
@Observable
final class NotificationSettingsStore {
    private static let enabledPreferenceKey = "notifications.newEpisodes.enabled"
    /// Left behind by the retired push-server sync; removed on load.
    private static let legacyPendingReconciliationPreferenceKey = "notifications.newEpisodes.pendingReconciliation"

    private(set) var isEnabled = false
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var isWorking = false
    private(set) var lastErrorMessage: String?

    @ObservationIgnored private let authorizationService: any NotificationAuthorizationProviding
    @ObservationIgnored private let backgroundRefresh: any BackgroundFeedRefreshScheduling
    @ObservationIgnored let ledger: NewEpisodeNotificationLedger

    init(
        authorizationService: any NotificationAuthorizationProviding = NotificationAuthorizationService(),
        backgroundRefresh: any BackgroundFeedRefreshScheduling = BGTaskSchedulerFeedRefreshScheduler(),
        ledger: NewEpisodeNotificationLedger = NewEpisodeNotificationLedger()
    ) {
        self.authorizationService = authorizationService
        self.backgroundRefresh = backgroundRefresh
        self.ledger = ledger
    }

    var statusText: String {
        if isWorking {
            return "Updating"
        }
        guard isEnabled else {
            return "Off"
        }
        guard canDeliver else {
            return NotificationAuthorizationService.label(for: authorizationStatus)
        }
        return "On"
    }

    var isPermissionDenied: Bool {
        authorizationStatus == .denied
    }

    /// Enabled and allowed to post.
    var canDeliver: Bool {
        isEnabled && NotificationAuthorizationService.allowsDelivery(authorizationStatus)
    }

    func load(modelContext: ModelContext) async {
        isEnabled = (try? LocalPreferenceRecord.preference(
            forKey: Self.enabledPreferenceKey,
            modelContext: modelContext
        ))?.value == "true"
        if (try? LocalPreferenceRecord.preference(
            forKey: Self.legacyPendingReconciliationPreferenceKey,
            modelContext: modelContext
        )) != nil {
            try? LocalPreferenceRecord.deletePreferences(
                forKey: Self.legacyPendingReconciliationPreferenceKey,
                modelContext: modelContext
            )
            try? modelContext.save()
        }
        authorizationStatus = await authorizationService.authorizationStatus()
    }

    func setEnabled(_ enabled: Bool, modelContext: ModelContext) async {
        guard !isWorking else {
            return
        }
        isWorking = true
        lastErrorMessage = nil
        defer { isWorking = false }

        if enabled {
            do {
                authorizationStatus = try await authorizationService.requestAuthorization()
            } catch {
                lastErrorMessage = error.localizedDescription
                return
            }
            guard NotificationAuthorizationService.allowsDelivery(authorizationStatus) else {
                lastErrorMessage = NotificationAuthorizationService.permissionUnavailableMessage(for: authorizationStatus)
                return
            }
        }

        do {
            try LocalPreferenceRecord.upsert(
                key: Self.enabledPreferenceKey,
                value: enabled ? "true" : "false",
                modelContext: modelContext
            )
            try modelContext.save()
            isEnabled = enabled
        } catch {
            lastErrorMessage = error.localizedDescription
            return
        }
        if enabled {
            scheduleBackgroundRefresh()
        } else {
            backgroundRefresh.cancel()
        }
    }

    /// Reloads the stored preference and permission, and keeps the
    /// background check scheduled while notifications can be delivered.
    func refreshIfNeeded(modelContext: ModelContext) async {
        await load(modelContext: modelContext)
        if canDeliver {
            scheduleBackgroundRefresh()
        } else if isEnabled {
            lastErrorMessage = NotificationAuthorizationService.permissionUnavailableMessage(for: authorizationStatus)
        }
    }

    func scheduleBackgroundRefresh() {
        guard isEnabled else {
            return
        }
        // Simulators and Background App Refresh being off both refuse the
        // submission; foreground refreshes still record new episodes.
        try? backgroundRefresh.submit(
            earliestBeginDate: .now.addingTimeInterval(BGTaskSchedulerFeedRefreshScheduler.interval)
        )
    }

    func resetAfterDataNuke() async {
        backgroundRefresh.cancel()
        isEnabled = false
        isWorking = false
        lastErrorMessage = nil
        await ledger.reset()
    }
}
