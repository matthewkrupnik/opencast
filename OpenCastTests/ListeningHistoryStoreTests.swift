import Foundation
import SwiftData
import Testing
@testable import OpenCast

@MainActor
@Suite("Listening history store")
struct ListeningHistoryStoreTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("A session opens at the start position, extends with progress, and closes at the stop")
    func sessionLifecycle() throws {
        let (store, context) = try makeStore()

        store.beginSession(episodeID: "e1", podcastID: "p1", position: 120, duration: 3600, hadDownload: true, modelContext: context, now: start)
        store.updateSession(episodeID: "e1", position: 600, duration: 3600, modelContext: context, now: start + 480)
        store.updateSession(episodeID: "e1", position: 900, duration: 3600, closes: true, modelContext: context, now: start + 780)

        let entry = try #require(store.entries.first)
        #expect(store.entries.count == 1)
        #expect(entry.kind == .session)
        #expect(entry.startPosition == 120)
        #expect(entry.endPosition == 900)
        #expect(entry.hadDownload)
        #expect(!entry.isOpen)

        // Progress for a closed session changes nothing.
        store.updateSession(episodeID: "e1", position: 1200, duration: 3600, modelContext: context, now: start + 1000)
        #expect(store.entries.first?.endPosition == 900)
    }

    @Test("A short pause that resumes in place continues the session; a long one starts a new row")
    func resumeMerging() throws {
        let (store, context) = try makeStore()

        store.beginSession(episodeID: "e1", podcastID: "p1", position: 0, duration: 3600, hadDownload: false, modelContext: context, now: start)
        store.updateSession(episodeID: "e1", position: 300, duration: 3600, closes: true, modelContext: context, now: start + 300)
        store.beginSession(episodeID: "e1", podcastID: "p1", position: 302, duration: 3600, hadDownload: false, modelContext: context, now: start + 360)
        #expect(store.entries.count == 1)
        #expect(store.entries.first?.startPosition == 0)
        #expect(store.entries.first?.isOpen == true)

        store.updateSession(episodeID: "e1", position: 600, duration: 3600, closes: true, modelContext: context, now: start + 660)
        store.beginSession(episodeID: "e1", podcastID: "p1", position: 600, duration: 3600, hadDownload: false, modelContext: context, now: start + 660 + 3600)
        #expect(store.entries.count == 2)
        #expect(store.entries.first?.startPosition == 600)
    }

    @Test("Finishing marks the latest session played to the end")
    func finishMarksSession() throws {
        let (store, context) = try makeStore()

        store.beginSession(episodeID: "e1", podcastID: "p1", position: 1800, duration: 3600, hadDownload: true, modelContext: context, now: start)
        store.recordFinish(episodeID: "e1", duration: 3600, modelContext: context, now: start + 1800)

        let entry = try #require(store.entries.first)
        #expect(entry.didFinish)
        #expect(entry.endPosition == 3600)
        #expect(entry.startPosition == 1800)
        #expect(!entry.isOpen)
    }

    @Test("Mark Played records the position it replaced")
    func markedPlayedEntry() throws {
        let (store, context) = try makeStore()

        store.recordMarkedPlayed(episodeID: "e1", podcastID: "p1", priorPosition: 420, duration: 3600, hadDownload: true, modelContext: context, now: start)

        let entry = try #require(store.entries.first)
        #expect(entry.kind == .markedPlayed)
        #expect(entry.startPosition == 420)
        #expect(entry.hadDownload)
    }

    @Test("Retention keeps a week, and never fewer than the ten newest entries")
    func retention() throws {
        let (store, context) = try makeStore()
        let day: TimeInterval = 24 * 60 * 60

        // Twelve old entries, a month back.
        for index in 0..<12 {
            store.recordMarkedPlayed(episodeID: "old-\(index)", podcastID: "p1", priorPosition: 0, duration: nil, hadDownload: false, modelContext: context, now: start - 30 * day + Double(index))
        }
        store.load(modelContext: context, now: start)
        #expect(store.entries.count == 10)
        #expect(store.entries.first?.episodeID == "old-11")

        // Fifteen recent ones push every old entry out.
        for index in 0..<15 {
            store.recordMarkedPlayed(episodeID: "new-\(index)", podcastID: "p1", priorPosition: 0, duration: nil, hadDownload: false, modelContext: context, now: start + Double(index))
        }
        #expect(store.entries.count == 15)
        #expect(store.entries.allSatisfy { $0.episodeID.hasPrefix("new-") })
    }

    @Test("Launch closes sessions left open by a killed process")
    func loadClosesOpenSessions() throws {
        let (store, context) = try makeStore()
        store.beginSession(episodeID: "e1", podcastID: "p1", position: 0, duration: nil, hadDownload: false, modelContext: context, now: start)

        let relaunched = ListeningHistoryStore()
        relaunched.load(modelContext: context, now: start + 60)
        #expect(relaunched.entries.first?.isOpen == false)
    }

    @Test("Clearing a show removes only its entries")
    func clearForPodcast() throws {
        let (store, context) = try makeStore()
        store.recordMarkedPlayed(episodeID: "e1", podcastID: "p1", priorPosition: 0, duration: nil, hadDownload: false, modelContext: context, now: start)
        store.recordMarkedPlayed(episodeID: "e2", podcastID: "p2", priorPosition: 0, duration: nil, hadDownload: false, modelContext: context, now: start + 1)

        store.clear(forPodcastID: "p1", modelContext: context)
        #expect(store.entries.map(\.episodeID) == ["e2"])
    }

    private func makeStore() throws -> (ListeningHistoryStore, ModelContext) {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        return (ListeningHistoryStore(), ModelContext(container))
    }
}
