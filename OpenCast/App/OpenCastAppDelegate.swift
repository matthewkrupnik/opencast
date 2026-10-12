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
        BGTaskSchedulerFeedRefreshScheduler.register { task in
            let runtime = OpenCastAppRuntime.shared
            BackgroundFeedRefreshRunner.run(
                task: task,
                appModel: runtime.appModel,
                modelContext: runtime.modelContainer.mainContext
            )
        }

        return true
    }

    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        intent is INPlayMediaIntent ? siriPlayMediaHandler : nil
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let route = Self.episodeRoute(from: response.notification)

        completionHandler()

        if let route {
            Self.deliverEpisodeRoute(route)
        }
    }

    nonisolated private static func deliverEpisodeRoute(_ route: RemoteEpisodeNotificationRoute) {
        Task { @MainActor in
            await Task.yield()
            #if DEBUG || INTERNAL_NOTIFICATIONS_DIAGNOSTICS
            RemoteEpisodeNotificationRouteDiagnostics.shared.record("Delegate Delivered", route: route)
            #endif
            RemoteEpisodeNotificationRouteBridge.shared.didReceive(route: route)
        }
    }

    private func registerNotificationCategories() {
        UNUserNotificationCenter.current().setNotificationCategories(
            OpenCastNotificationCategory.registrationCategories()
        )
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
