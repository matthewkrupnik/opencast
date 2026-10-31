import Foundation
import Intents
import UIKit
import UserNotifications

final class OpenCastAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private lazy var siriPlayMediaHandler: SiriPlayMediaHandler = {
        let runtime = OpenCastAppRuntime.shared
        return SiriPlayMediaHandler(
            appModel: runtime.appModel,
            modelContext: runtime.modelContainer.mainContext
        )
    }()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerNotificationCategories()
        UNUserNotificationCenter.current().delegate = self
        connectBackgroundDownloads()

        return true
    }

    /// The background download session reconnects at launch so iOS can hand
    /// over downloads that finished while the app wasn't running.
    private func connectBackgroundDownloads() {
        let runtime = OpenCastAppRuntime.shared
        guard !runtime.launchConfiguration.usesInMemoryStore else {
            return
        }
        BackgroundEpisodeAudioDownloader.shared.setOrphanFinishedHandler {
            Task {
                await runtime.appModel.downloads.adoptFinishedBackgroundDownloads(
                    modelContext: runtime.modelContainer.mainContext
                )
            }
        }
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundEpisodeAudioDownloader.sessionIdentifier else {
            completionHandler()
            return
        }
        // UIKit's handler; it is called back on the main actor.
        nonisolated(unsafe) let systemCompletionHandler = completionHandler
        BackgroundEpisodeAudioDownloader.shared.handleEvents {
            systemCompletionHandler()
        }
    }

    /// A new-episode push (`content-available`) wakes the app: it refreshes
    /// that show and starts its automatic downloads. iOS allows about 30
    /// seconds, so the work stops waiting at 25; downloads already handed to
    /// the background session keep going.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard let feedURL = Self.newEpisodeFeedURL(from: userInfo) else {
            return .noData
        }
        let runtime = OpenCastAppRuntime.shared
        return await withCheckedContinuation { continuation in
            let reply = PushWakeReply(continuation)
            let work = Task {
                let started = await runtime.appModel.handleNewEpisodePush(
                    feedURL: feedURL,
                    modelContext: runtime.modelContainer.mainContext
                )
                reply.send(started ? .newData : .noData)
            }
            Task {
                try? await Task.sleep(for: .seconds(25))
                work.cancel()
                reply.send(.failed)
            }
        }
    }

    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        intent is INPlayMediaIntent ? siriPlayMediaHandler : nil
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard !RemoteNotificationRegistrationBridge.shared.didRegister(deviceToken: deviceToken) else {
            return
        }
        // Reconcile unsolicited token changes through the same opt-in and serialization gates.
        Task {
            let runtime = OpenCastAppRuntime.shared
            await runtime.appModel.notificationSettings.refreshIfNeeded(
                activePodcastIDs: runtime.appModel.library.activePodcastIDs,
                modelContext: runtime.modelContainer.mainContext
            )
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        RemoteNotificationRegistrationBridge.shared.didFailToRegister(error: error)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        #if DEBUG || INTERNAL_NOTIFICATIONS_DIAGNOSTICS
        if Self.notificationKind(from: notification) == "diagnostic" {
            Self.deliverDiagnosticNotification()
        }
        #endif

        completionHandler([.banner, .list, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let notification = response.notification
        let isDiagnostic = Self.notificationKind(from: notification) == "diagnostic"
        let route = Self.episodeRoute(from: notification)

        completionHandler()

        #if DEBUG || INTERNAL_NOTIFICATIONS_DIAGNOSTICS
        if isDiagnostic {
            Self.deliverDiagnosticNotification()
        } else if let route {
            Self.deliverEpisodeRoute(route)
        }
        #else
        if let route {
            Self.deliverEpisodeRoute(route)
        }
        #endif
    }

    #if DEBUG || INTERNAL_NOTIFICATIONS_DIAGNOSTICS
    nonisolated private static func deliverDiagnosticNotification() {
        Task { @MainActor in
            // Let UIKit's notification completion path unwind before mutating app route state.
            await Task.yield()
            RemoteNotificationRegistrationBridge.shared.didReceiveDiagnosticNotification()
        }
    }
    #endif

    nonisolated private static func deliverEpisodeRoute(_ route: RemoteEpisodeNotificationRoute) {
        Task { @MainActor in
            await Task.yield()
            #if DEBUG || INTERNAL_NOTIFICATIONS_DIAGNOSTICS
            RemoteEpisodeNotificationRouteDiagnostics.shared.record("Delegate Delivered", route: route)
            #endif
            RemoteEpisodeNotificationRouteBridge.shared.didReceive(route: route)
        }
    }

    nonisolated private static func notificationKind(from notification: UNNotification) -> String? {
        let userInfo = notification.request.content.userInfo
        let opencastPayload = userInfo["opencast"] as? [String: Any]
        return opencastPayload?["kind"] as? String
    }

    private func registerNotificationCategories() {
        UNUserNotificationCenter.current().setNotificationCategories(
            OpenCastNotificationCategory.registrationCategories()
        )
    }

    private static func newEpisodeFeedURL(from userInfo: [AnyHashable: Any]) -> String? {
        guard let opencastPayload = userInfo["opencast"] as? [String: Any],
              opencastPayload["kind"] as? String == "episode"
        else {
            return nil
        }
        return opencastPayload["feed_url"] as? String
    }

    nonisolated private static func episodeRoute(from notification: UNNotification) -> RemoteEpisodeNotificationRoute? {
        let userInfo = notification.request.content.userInfo
        guard let opencastPayload = userInfo["opencast"] as? [String: Any],
              opencastPayload["kind"] as? String == "episode",
              let feedURL = opencastPayload["feed_url"] as? String,
              let episodeID = opencastPayload["episode_id"] as? String
        else {
            return nil
        }

        return RemoteEpisodeNotificationRoute(
            feedURL: feedURL,
            episodeID: episodeID,
            episodeTitle: opencastPayload["episode_title"] as? String
        )
    }
}

/// Answers a push wake once: the work or the deadline, whichever is first.
@MainActor
private final class PushWakeReply {
    private var continuation: CheckedContinuation<UIBackgroundFetchResult, Never>?

    init(_ continuation: CheckedContinuation<UIBackgroundFetchResult, Never>) {
        self.continuation = continuation
    }

    func send(_ result: UIBackgroundFetchResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
