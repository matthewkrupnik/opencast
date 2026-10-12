import BackgroundTasks
import Foundation

/// The periodic background feed check that powers local new-episode
/// notifications. iOS decides when (and whether) it runs.
protocol BackgroundFeedRefreshScheduling {
    func submit(earliestBeginDate: Date) throws
    func cancel()
}

struct BGTaskSchedulerFeedRefreshScheduler: BackgroundFeedRefreshScheduling {
    static let taskIdentifier = "mk.lan.opencast.feed-refresh"
    static let interval: TimeInterval = 45 * 60

    /// Must run before the app finishes launching.
    @discardableResult
    static func register(handler: @escaping @MainActor (BGAppRefreshTask) -> Void) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: .main) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            MainActor.assumeIsolated {
                handler(task)
            }
        }
    }

    func submit(earliestBeginDate: Date) throws {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = earliestBeginDate
        try BGTaskScheduler.shared.submit(request)
    }

    func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    }
}
