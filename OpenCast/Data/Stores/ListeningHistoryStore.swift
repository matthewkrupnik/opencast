import Foundation
import Observation
import SwiftData
import os

/// Device-local listening history: each play-to-pause stretch and each Mark
/// Played, newest first, so a mistaken skip, a night of playing on, or a
/// finished-and-swept episode can be put back. Keeps a week, and never fewer
/// than the newest `minimumRetainedCount` entries however old.
@Observable
final class ListeningHistoryStore {
    static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60
    static let minimumRetainedCount = 10
    /// A pause shorter than this that picks up where it left off continues
    /// the same session instead of starting a new row.
    static let resumeMergeInterval: TimeInterval = 5 * 60
    static let resumeMergePositionTolerance: TimeInterval = 30

    private static let logger = Logger(subsystem: "mk.lan.opencast", category: "ListeningHistory")

    private(set) var entries: [ListeningHistoryEntry] = []

    func load(modelContext: ModelContext, now: Date = .now) {
        do {
            for record in try fetchRecords(modelContext: modelContext) where record.isOpen {
                record.isOpen = false
            }
            try prune(modelContext: modelContext, now: now)
            try save(modelContext)
        } catch {
            Self.logger.error("Unable to load listening history: \(error.localizedDescription)")
        }
    }

    func beginSession(
        episodeID: String,
        podcastID: String,
        position: TimeInterval,
        duration: TimeInterval?,
        hadDownload: Bool,
        modelContext: ModelContext,
        now: Date = .now
    ) {
        do {
            let records = try fetchRecords(modelContext: modelContext)
            if let latest = records.first,
               latest.kind == ListeningHistoryEntry.Kind.session.rawValue,
               latest.episodeID == episodeID,
               !latest.didFinish,
               now.timeIntervalSince(latest.endedAt) < Self.resumeMergeInterval,
               abs(position - latest.endPosition) < Self.resumeMergePositionTolerance {
                latest.isOpen = true
                latest.endedAt = now
            } else {
                for record in records where record.isOpen {
                    record.isOpen = false
                }
                modelContext.insert(ListeningHistoryRecord(
                    kind: .session,
                    episodeID: episodeID,
                    podcastID: podcastID,
                    startPosition: position,
                    endPosition: position,
                    duration: duration,
                    startedAt: now,
                    endedAt: now,
                    hadDownload: hadDownload,
                    isOpen: true
                ))
                try prune(modelContext: modelContext, now: now)
            }
            try save(modelContext)
        } catch {
            Self.logger.error("Unable to record a listening session: \(error.localizedDescription)")
        }
    }

    /// Extends the episode's open session; a no-op when none is open.
    func updateSession(
        episodeID: String,
        position: TimeInterval,
        duration: TimeInterval?,
        closes: Bool = false,
        modelContext: ModelContext,
        now: Date = .now
    ) {
        do {
            guard let record = try fetchRecords(modelContext: modelContext).first(where: {
                $0.isOpen && $0.episodeID == episodeID
            }) else {
                return
            }
            record.endPosition = position
            record.duration = duration ?? record.duration
            record.endedAt = now
            record.isOpen = !closes
            try save(modelContext)
        } catch {
            Self.logger.error("Unable to update a listening session: \(error.localizedDescription)")
        }
    }

    /// Closes whatever session is open without moving its end, for when the
    /// player has already moved on to another episode.
    func closeOpenSessions(modelContext: ModelContext) {
        do {
            let openRecords = try fetchRecords(modelContext: modelContext).filter { $0.isOpen }
            guard !openRecords.isEmpty else {
                return
            }
            for record in openRecords {
                record.isOpen = false
            }
            try save(modelContext)
        } catch {
            Self.logger.error("Unable to close listening sessions: \(error.localizedDescription)")
        }
    }

    /// Marks the episode's latest session as having played to the end.
    func recordFinish(
        episodeID: String,
        duration: TimeInterval?,
        modelContext: ModelContext,
        now: Date = .now
    ) {
        do {
            guard let record = try fetchRecords(modelContext: modelContext).first(where: {
                $0.episodeID == episodeID && $0.kind == ListeningHistoryEntry.Kind.session.rawValue
            }) else {
                return
            }
            record.didFinish = true
            record.isOpen = false
            record.duration = duration ?? record.duration
            record.endPosition = record.duration ?? record.endPosition
            record.endedAt = now
            try save(modelContext)
        } catch {
            Self.logger.error("Unable to record a finished episode: \(error.localizedDescription)")
        }
    }

    func recordMarkedPlayed(
        episodeID: String,
        podcastID: String,
        priorPosition: TimeInterval,
        duration: TimeInterval?,
        hadDownload: Bool,
        modelContext: ModelContext,
        now: Date = .now
    ) {
        do {
            for record in try fetchRecords(modelContext: modelContext) where record.isOpen {
                record.isOpen = false
            }
            modelContext.insert(ListeningHistoryRecord(
                kind: .markedPlayed,
                episodeID: episodeID,
                podcastID: podcastID,
                startPosition: priorPosition,
                endPosition: duration ?? priorPosition,
                duration: duration,
                startedAt: now,
                endedAt: now,
                hadDownload: hadDownload,
                isOpen: false
            ))
            try prune(modelContext: modelContext, now: now)
            try save(modelContext)
        } catch {
            Self.logger.error("Unable to record Mark Played: \(error.localizedDescription)")
        }
    }

    func clear(modelContext: ModelContext) {
        deleteRecords(modelContext: modelContext) { _ in true }
    }

    func clear(forPodcastID podcastID: String, modelContext: ModelContext) {
        deleteRecords(modelContext: modelContext) { $0.podcastID == podcastID }
    }

    /// Forgets the published entries without touching the store, for a data
    /// nuke that has already deleted every row.
    func reset() {
        entries = []
    }

    private func deleteRecords(modelContext: ModelContext, matching isCleared: (ListeningHistoryRecord) -> Bool) {
        do {
            for record in try fetchRecords(modelContext: modelContext) where isCleared(record) {
                modelContext.delete(record)
            }
            try save(modelContext)
        } catch {
            Self.logger.error("Unable to clear listening history: \(error.localizedDescription)")
        }
    }

    private func prune(modelContext: ModelContext, now: Date) throws {
        let cutoff = now.addingTimeInterval(-Self.retentionInterval)
        for (index, record) in try fetchRecords(modelContext: modelContext).enumerated()
        where index >= Self.minimumRetainedCount && record.startedAt < cutoff && !record.isOpen {
            modelContext.delete(record)
        }
    }

    private func save(_ modelContext: ModelContext) throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
        entries = try fetchRecords(modelContext: modelContext).map(ListeningHistoryEntry.init)
    }

    private func fetchRecords(modelContext: ModelContext) throws -> [ListeningHistoryRecord] {
        try modelContext.fetch(FetchDescriptor<ListeningHistoryRecord>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))
    }
}
