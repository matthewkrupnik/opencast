import Testing
@testable import OpenCast

@MainActor
@Suite("Ad-free pass charging catch-up")
struct AdFreePassChargingCatchUpTests {
    @Test("Schedules only after registering and only with pending work")
    func schedulesOnlyWithPendingWork() {
        let scheduler = FakeChargingScheduler()
        let catchUp = AdFreePassChargingCatchUp(scheduler: scheduler)
        var pending = true
        catchUp.hasPendingWork = { pending }

        catchUp.scheduleIfNeeded()
        #expect(scheduler.submitCount == 0)

        catchUp.register()
        catchUp.scheduleIfNeeded()
        #expect(scheduler.submitCount == 1)

        pending = false
        catchUp.scheduleIfNeeded()
        #expect(scheduler.submitCount == 1)
    }

    @Test("An interruption outside a run reschedules; a drain with nothing left cancels")
    func terminalOutsideRun() {
        let scheduler = FakeChargingScheduler()
        let catchUp = AdFreePassChargingCatchUp(scheduler: scheduler)
        var pending = true
        catchUp.hasPendingWork = { pending }
        catchUp.register()

        catchUp.noteQueueTerminal(.interrupted)
        #expect(scheduler.submitCount == 1)

        pending = false
        catchUp.noteQueueTerminal(.drained(completedCount: 1, failedCount: 0))
        #expect(scheduler.cancelCount == 1)
    }

    @Test("A launch starts the work and completes successfully when the queue drains")
    func launchDrains() async {
        let scheduler = FakeChargingScheduler()
        let catchUp = AdFreePassChargingCatchUp(scheduler: scheduler)
        var started = false
        catchUp.isQueueRunning = { true }
        catchUp.startWork = { started = true }
        catchUp.register()

        let handle = FakeChargingHandle()
        scheduler.launch(handle)
        #expect(catchUp.isRunning)
        await Task.yield()
        await Task.yield()
        #expect(started)
        #expect(handle.completion == nil)

        catchUp.noteQueueTerminal(.drained(completedCount: 2, failedCount: 0))
        #expect(handle.completion == true)
        #expect(!catchUp.isRunning)
    }

    @Test("A launch with nothing to drain completes right away")
    func launchWithNothingQueued() async {
        let scheduler = FakeChargingScheduler()
        let catchUp = AdFreePassChargingCatchUp(scheduler: scheduler)
        catchUp.isQueueRunning = { false }
        catchUp.register()

        let handle = FakeChargingHandle()
        scheduler.launch(handle)
        for _ in 0..<5 { await Task.yield() }
        #expect(handle.completion == true)
    }

    @Test("Expiration stops the pass, fails the task, and asks for another run")
    func expirationReschedules() async {
        let scheduler = FakeChargingScheduler()
        let catchUp = AdFreePassChargingCatchUp(scheduler: scheduler)
        var expired = false
        catchUp.hasPendingWork = { true }
        catchUp.isQueueRunning = { true }
        catchUp.onExpiration = { expired = true }
        catchUp.register()

        let handle = FakeChargingHandle()
        scheduler.launch(handle)
        for _ in 0..<5 { await Task.yield() }
        handle.expire()
        for _ in 0..<5 { await Task.yield() }

        #expect(expired)
        #expect(handle.completion == false)
        #expect(scheduler.submitCount == 1)

        // The interruption the expiration causes arrives after the run ended.
        catchUp.noteQueueTerminal(.interrupted)
        #expect(handle.completionCount == 1)
    }
}

@MainActor
private final class FakeChargingScheduler: ChargingCatchUpScheduling {
    private(set) var submitCount = 0
    private(set) var cancelCount = 0
    private var onLaunch: (@MainActor @Sendable (any ChargingCatchUpTaskHandle) -> Void)?

    func registerLaunchHandler(
        identifier: String,
        onLaunch: @escaping @MainActor @Sendable (any ChargingCatchUpTaskHandle) -> Void
    ) -> Bool {
        self.onLaunch = onLaunch
        return true
    }

    func submit(identifier: String) throws {
        submitCount += 1
    }

    func cancel(identifier: String) {
        cancelCount += 1
    }

    func launch(_ handle: FakeChargingHandle) {
        onLaunch?(handle)
    }
}

@MainActor
private final class FakeChargingHandle: ChargingCatchUpTaskHandle {
    private(set) var completion: Bool?
    private(set) var completionCount = 0
    private var expirationHandler: (@Sendable () -> Void)?

    func setTaskCompleted(success: Bool) {
        completion = success
        completionCount += 1
    }

    func setExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
        expirationHandler = handler
    }

    func expire() {
        expirationHandler?()
    }
}
