import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import OpenCast

@MainActor
@Suite("Notification settings store")
struct NotificationSettingsStoreTests {
    @Test("Enabling asks for permission, saves the preference, and schedules the background check")
    func enablingSchedulesBackgroundCheck() async throws {
        let context = try makeContext()
        let authorization = StubNotificationAuthorizationService(requestResult: .authorized)
        let scheduler = RecordingFeedRefreshScheduler()
        let store = makeStore(authorization, scheduler)

        await store.setEnabled(true, modelContext: context)

        #expect(authorization.requestCount == 1)
        #expect(store.isEnabled)
        #expect(store.statusText == "On")
        #expect(scheduler.submissions == 1)

        let reloaded = makeStore(StubNotificationAuthorizationService(status: .authorized), RecordingFeedRefreshScheduler())
        await reloaded.load(modelContext: context)
        #expect(reloaded.isEnabled)
    }

    @Test("A denied permission leaves notifications off with a message")
    func deniedPermissionStaysOff() async throws {
        let context = try makeContext()
        let scheduler = RecordingFeedRefreshScheduler()
        let store = makeStore(StubNotificationAuthorizationService(requestResult: .denied), scheduler)

        await store.setEnabled(true, modelContext: context)

        #expect(!store.isEnabled)
        #expect(store.isPermissionDenied)
        #expect(store.lastErrorMessage == "Notification permission is denied.")
        #expect(scheduler.submissions == 0)
    }

    @Test("Disabling cancels the background check")
    func disablingCancelsBackgroundCheck() async throws {
        let context = try makeContext()
        let scheduler = RecordingFeedRefreshScheduler()
        let store = makeStore(StubNotificationAuthorizationService(requestResult: .authorized), scheduler)
        await store.setEnabled(true, modelContext: context)

        await store.setEnabled(false, modelContext: context)

        #expect(!store.isEnabled)
        #expect(store.statusText == "Off")
        #expect(scheduler.cancellations == 1)
    }

    @Test("Refreshing keeps the check scheduled only while delivery is allowed")
    func refreshSchedulesOnlyWhenDeliverable() async throws {
        let context = try makeContext()
        let authorization = StubNotificationAuthorizationService(requestResult: .authorized)
        let scheduler = RecordingFeedRefreshScheduler()
        let store = makeStore(authorization, scheduler)
        await store.setEnabled(true, modelContext: context)

        await store.refreshIfNeeded(modelContext: context)
        #expect(scheduler.submissions == 2)

        authorization.status = .denied
        await store.refreshIfNeeded(modelContext: context)
        #expect(scheduler.submissions == 2)
        #expect(store.statusText == "Denied")
    }

    @Test("Resetting after a data wipe turns notifications off and clears the ledger")
    func resetAfterDataNuke() async throws {
        let context = try makeContext()
        let ledgerURL = FileManager.default.temporaryDirectory.appending(path: "ledger-\(UUID().uuidString).json")
        let ledger = NewEpisodeNotificationLedger(fileURL: ledgerURL)
        _ = await ledger.admit([NewEpisodeNotificationTests.candidate("a")])
        let store = NotificationSettingsStore(
            authorizationService: StubNotificationAuthorizationService(requestResult: .authorized),
            backgroundRefresh: RecordingFeedRefreshScheduler(),
            ledger: ledger
        )
        await store.setEnabled(true, modelContext: context)

        await store.resetAfterDataNuke()

        #expect(!store.isEnabled)
        #expect(await ledger.admit([NewEpisodeNotificationTests.candidate("a")]).count == 1)
    }

    private func makeStore(
        _ authorization: StubNotificationAuthorizationService,
        _ scheduler: RecordingFeedRefreshScheduler
    ) -> NotificationSettingsStore {
        NotificationSettingsStore(
            authorizationService: authorization,
            backgroundRefresh: scheduler,
            ledger: NewEpisodeNotificationLedger(
                fileURL: FileManager.default.temporaryDirectory.appending(path: "ledger-\(UUID().uuidString).json")
            )
        )
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try OpenCastModelContainerFactory.make(inMemory: true))
    }
}

private final class StubNotificationAuthorizationService: NotificationAuthorizationProviding {
    var status: UNAuthorizationStatus
    var requestResult: UNAuthorizationStatus
    private(set) var requestCount = 0

    init(status: UNAuthorizationStatus = .notDetermined, requestResult: UNAuthorizationStatus = .authorized) {
        self.status = status
        self.requestResult = requestResult
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization() async throws -> UNAuthorizationStatus {
        requestCount += 1
        status = requestResult
        return requestResult
    }
}

private final class RecordingFeedRefreshScheduler: BackgroundFeedRefreshScheduling {
    private(set) var submissions = 0
    private(set) var cancellations = 0

    func submit(earliestBeginDate: Date) throws {
        submissions += 1
    }

    func cancel() {
        cancellations += 1
    }
}
