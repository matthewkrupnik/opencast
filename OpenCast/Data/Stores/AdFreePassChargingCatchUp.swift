@preconcurrency import BackgroundTasks
import Foundation
import OSLog

@MainActor
protocol ChargingCatchUpTaskHandle: AnyObject {
    func setTaskCompleted(success: Bool)
    func setExpirationHandler(_ handler: @escaping @Sendable () -> Void)
}

@MainActor
protocol ChargingCatchUpScheduling {
    func registerLaunchHandler(
        identifier: String,
        onLaunch: @escaping @MainActor @Sendable (any ChargingCatchUpTaskHandle) -> Void
    ) -> Bool
    func submit(identifier: String) throws
    func cancel(identifier: String)
}

/// Drains the ad-free pass queue (transcribe, then detect ads) in a
/// `BGProcessingTask` that iOS runs only on external power with network —
/// typically overnight. Covers what the continued-processing card cannot:
/// passes queued while the app was in the background (a new episode that
/// auto-downloaded after a push wake) and passes paused when the app left
/// the foreground. The queue persists its items, so a cold launch restores
/// them before draining.
final class AdFreePassChargingCatchUp {
    static let identifier = "mk.lan.opencast.charging-catch-up"

    private static let logger = Logger(subsystem: "mk.lan.opencast", category: "ChargingCatchUp")

    private let scheduler: any ChargingCatchUpScheduling
    private var hasRegistered = false
    private var handle: (any ChargingCatchUpTaskHandle)?
    private var launchSequence = 0

    var hasPendingWork: () -> Bool = { false }
    var isQueueRunning: () -> Bool = { false }
    /// Loads the persisted queue and starts or resumes its drain.
    var startWork: () async -> Void = {}
    /// Stops the running pass resumably before the system suspends the app.
    var onExpiration: () -> Void = {}

    init(scheduler: any ChargingCatchUpScheduling = BGTaskSchedulerChargingCatchUpScheduler()) {
        self.scheduler = scheduler
    }

    var isRunning: Bool {
        handle != nil
    }

    /// Must run before the app finishes launching, or iOS will not deliver
    /// the task to a background launch.
    func register() {
        guard !hasRegistered else {
            return
        }
        hasRegistered = scheduler.registerLaunchHandler(identifier: Self.identifier) { [weak self] handle in
            self?.handleLaunch(handle)
        }
        record("register success=\(hasRegistered)")
    }

    /// Asks iOS for a charging run when queued work remains. Submitting
    /// again replaces the earlier request, so callers need not deduplicate.
    func scheduleIfNeeded() {
        guard hasRegistered, !isRunning, hasPendingWork() else {
            return
        }
        do {
            try scheduler.submit(identifier: Self.identifier)
            record("submit success")
        } catch {
            Self.logger.error("charging catch-up submit failed: \(error.localizedDescription, privacy: .public)")
            record("submit failed error=\(error.localizedDescription)")
        }
    }

    func noteQueueTerminal(_ outcome: AdFreePassQueueTerminalOutcome) {
        guard isRunning else {
            switch outcome {
            case .interrupted:
                scheduleIfNeeded()
            case .drained, .awaitingConsent:
                if !hasPendingWork() {
                    scheduler.cancel(identifier: Self.identifier)
                }
            }
            return
        }

        switch outcome {
        case .drained, .awaitingConsent:
            finish(success: true)
        case .interrupted:
            finish(success: false)
            scheduleIfNeeded()
        }
    }

    private func handleLaunch(_ launchedHandle: any ChargingCatchUpTaskHandle) {
        guard handle == nil else {
            launchedHandle.setTaskCompleted(success: false)
            return
        }

        handle = launchedHandle
        launchSequence += 1
        let sequence = launchSequence
        launchedHandle.setExpirationHandler { [weak self] in
            Task { @MainActor in
                self?.expire(sequence: sequence)
            }
        }
        record("launch")

        Task { [weak self] in
            await self?.startWork()
            self?.finishIfIdle(sequence: sequence)
        }
    }

    private func finishIfIdle(sequence: Int) {
        guard isRunning, sequence == launchSequence, !isQueueRunning() else {
            return
        }
        record("nothing to drain pending=\(hasPendingWork())")
        finish(success: true)
    }

    private func expire(sequence: Int) {
        guard isRunning, sequence == launchSequence else {
            return
        }
        record("expired")
        onExpiration()
        finish(success: false)
        scheduleIfNeeded()
    }

    private func finish(success: Bool) {
        guard let handle else {
            return
        }
        self.handle = nil
        handle.setTaskCompleted(success: success)
        record("completed success=\(success)")
    }

    private func record(_ message: String) {
        Self.logger.log("\(message, privacy: .public)")
        AdFreePassBackgroundRunLog.record("charging-catch-up \(message)")
    }
}

struct BGTaskSchedulerChargingCatchUpScheduler: ChargingCatchUpScheduling {
    func registerLaunchHandler(
        identifier: String,
        onLaunch: @escaping @MainActor @Sendable (any ChargingCatchUpTaskHandle) -> Void
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                onLaunch(BGProcessingTaskHandleAdapter(task: processingTask))
            }
        }
    }

    func submit(identifier: String) throws {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresExternalPower = true
        // Ad detection sends the transcript to the analysis service.
        request.requiresNetworkConnectivity = true
        try BGTaskScheduler.shared.submit(request)
    }

    func cancel(identifier: String) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}

private final class BGProcessingTaskHandleAdapter: ChargingCatchUpTaskHandle {
    private let task: BGProcessingTask

    init(task: BGProcessingTask) {
        self.task = task
    }

    func setTaskCompleted(success: Bool) {
        task.setTaskCompleted(success: success)
    }

    func setExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
        task.expirationHandler = handler
    }
}
