import BackgroundTasks
import SwiftData

/// One background feed check: refresh feeds older than 30 minutes inside a
/// ~25-second budget so newly published episodes reach the new-episode
/// notifier. Partial progress publishes when the budget or iOS cuts it short.
@MainActor
enum BackgroundFeedRefreshRunner {
    static let budget: Duration = .seconds(25)
    static let staleAfter: TimeInterval = 30 * 60

    static func run(task: BGAppRefreshTask, appModel: OpenCastAppModel, modelContext: ModelContext) {
        let work = Task { @MainActor in
            await appModel.notificationSettings.load(modelContext: modelContext)
            // Always keep the next check scheduled while notifications are on.
            appModel.notificationSettings.scheduleBackgroundRefresh()
            guard appModel.notificationSettings.canDeliver else {
                return
            }
            await appModel.ensureCoreStoresLoaded(modelContext: modelContext)
            await appModel.library.refreshAllIfStale(modelContext: modelContext, staleAfter: staleAfter)
        }
        task.expirationHandler = {
            work.cancel()
        }
        Task { @MainActor in
            let deadline = Task {
                try await Task.sleep(for: budget)
                work.cancel()
            }
            await work.value
            deadline.cancel()
            task.setTaskCompleted(success: !work.isCancelled)
        }
    }
}
