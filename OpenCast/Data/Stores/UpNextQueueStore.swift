import Foundation
import Observation
import SwiftData
import SwiftUI

/// The rest of the playlist being played, in rule order: what plays after
/// the current episode. Persisted and synced so playback continues after a
/// relaunch. Only playing a playlist fills it; there is no user-facing queue.
@Observable
final class UpNextQueueStore {
    private(set) var items: [UpNextQueueItem] = []
    private(set) var lastErrorMessage: String?

    @ObservationIgnored var onQueueChanged: (() -> Void)?
    @ObservationIgnored private let saveModelContext: (ModelContext) throws -> Void

    init(
        saveModelContext: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.saveModelContext = saveModelContext
    }

    func load(
        resolveEpisode: (String) -> EpisodeListItemSnapshot?,
        mayPruneUnresolved: Bool,
        modelContext: ModelContext
    ) {
        do {
            let records = try modelContext.fetch(
                FetchDescriptor<UpNextQueueItemRecord>(
                    sortBy: [
                        SortDescriptor(\.sequence),
                        SortDescriptor(\.enqueuedAt),
                        SortDescriptor(\.episodeID)
                    ]
                )
            )
            let loadedItems: [UpNextQueueItem]
            if mayPruneUnresolved {
                var resolvedItems: [UpNextQueueItem] = []
                var seenEpisodeIDs: Set<String> = []
                var recordsChanged = false

                for record in records {
                    guard resolveEpisode(record.episodeID) != nil,
                          seenEpisodeIDs.insert(record.episodeID).inserted
                    else {
                        modelContext.delete(record)
                        recordsChanged = true
                        continue
                    }

                    let sequence = resolvedItems.count
                    if record.sequence != sequence {
                        record.sequence = sequence
                        recordsChanged = true
                    }
                    resolvedItems.append(Self.item(from: record, sequence: sequence))
                }

                if recordsChanged {
                    try saveModelContext(modelContext)
                }
                loadedItems = resolvedItems
            } else {
                loadedItems = records.map { Self.item(from: $0, sequence: $0.sequence) }
            }
            items = loadedItems
            lastErrorMessage = nil
            onQueueChanged?()
        } catch {
            modelContext.rollback()
            lastErrorMessage = "Unable to load the rest of the playlist: \(error.localizedDescription)"
        }
    }

    /// Appends the whole batch in array order. One save; a failure leaves the
    /// queue untouched.
    @discardableResult
    func enqueueLast(
        _ episodes: [EpisodeListItemSnapshot],
        source: String?,
        modelContext: ModelContext
    ) -> Bool {
        enqueue(episodes, source: source, modelContext: modelContext)
    }

    @discardableResult
    func remove(episodeID: String, modelContext: ModelContext) -> Bool {
        remove(episodeIDs: [episodeID], modelContext: modelContext)
    }

    @discardableResult
    func remove(episodeIDs: Set<String>, modelContext: ModelContext) -> Bool {
        guard !episodeIDs.isEmpty else {
            return true
        }

        do {
            let records = try modelContext.fetch(FetchDescriptor<UpNextQueueItemRecord>())
                .filter { episodeIDs.contains($0.episodeID) }
            let removesLoadedItems = items.contains { episodeIDs.contains($0.episodeID) }
            guard removesLoadedItems || !records.isEmpty else {
                return true
            }

            let previousItems = items
            items.removeAll { episodeIDs.contains($0.episodeID) }
            do {
                for record in records {
                    modelContext.delete(record)
                }
                try saveModelContext(modelContext)
                didMutate()
                return true
            } catch {
                modelContext.rollback()
                items = previousItems
                throw error
            }
        } catch {
            lastErrorMessage = "Unable to update the rest of the playlist: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func removeAll(forPodcastID podcastID: String, modelContext: ModelContext) -> Bool {
        do {
            let descriptor = FetchDescriptor<UpNextQueueItemRecord>(
                predicate: #Predicate { $0.podcastID == podcastID }
            )
            let records = try modelContext.fetch(descriptor)
            let removesLoadedItems = items.contains { $0.podcastID == podcastID }
            guard removesLoadedItems || !records.isEmpty else {
                return true
            }

            let previousItems = items
            items.removeAll { $0.podcastID == podcastID }
            do {
                for record in records {
                    modelContext.delete(record)
                }
                try saveModelContext(modelContext)
                didMutate()
                return true
            } catch {
                modelContext.rollback()
                items = previousItems
                throw error
            }
        } catch {
            lastErrorMessage = "Unable to update the rest of the playlist: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func clear(modelContext: ModelContext) -> Bool {
        do {
            let records = try modelContext.fetch(FetchDescriptor<UpNextQueueItemRecord>())
            guard !items.isEmpty || !records.isEmpty else {
                return true
            }

            let previousItems = items
            items = []
            do {
                for record in records {
                    modelContext.delete(record)
                }
                try saveModelContext(modelContext)
                didMutate()
                return true
            } catch {
                modelContext.rollback()
                items = previousItems
                throw error
            }
        } catch {
            lastErrorMessage = "Unable to update the rest of the playlist: \(error.localizedDescription)"
            return false
        }
    }

    func popNext(modelContext: ModelContext) -> UpNextQueuePopResult {
        guard let nextItem = items.first else {
            return .empty
        }

        let previousItems = items
        items.removeFirst()
        do {
            try deleteRecords(episodeID: nextItem.episodeID, modelContext: modelContext)
            try saveModelContext(modelContext)
            didMutate()
            return .item(nextItem)
        } catch {
            modelContext.rollback()
            items = previousItems
            let message = "Unable to play the next playlist episode: \(error.localizedDescription)"
            lastErrorMessage = message
            return .failure(message)
        }
    }

    func resetAfterDataNuke() {
        items = []
        lastErrorMessage = nil
        onQueueChanged?()
    }

    func consumeLastErrorMessage() -> String? {
        defer { lastErrorMessage = nil }
        return lastErrorMessage
    }

    /// Already-queued episodes move into the batch's slot and take its
    /// source; a repeat inside the batch keeps its first occurrence. The
    /// batch's sequences continue from its neighbour, so untouched rows keep
    /// their stored order without a rewrite.
    private func enqueue(
        _ episodes: [EpisodeListItemSnapshot],
        source: String?,
        modelContext: ModelContext
    ) -> Bool {
        var batchEpisodeIDs: Set<String> = []
        let batch = episodes.filter { batchEpisodeIDs.insert($0.episodeID).inserted }
        guard !batch.isEmpty else {
            return true
        }

        let previousItems = items
        let remainingItems = items.filter { !batchEpisodeIDs.contains($0.episodeID) }
        let firstSequence = (remainingItems.last?.sequence ?? -1) + 1
        let enqueuedAt = Date.now
        let addedItems = batch.enumerated().map { offset, episode in
            UpNextQueueItem(
                episodeID: episode.episodeID,
                podcastID: episode.podcastID,
                sequence: firstSequence + offset,
                enqueuedAt: enqueuedAt,
                sourcePlaylistID: source
            )
        }
        items = remainingItems + addedItems

        do {
            let records = try modelContext.fetch(FetchDescriptor<UpNextQueueItemRecord>())
            for record in records where batchEpisodeIDs.contains(record.episodeID) {
                modelContext.delete(record)
            }
            for item in addedItems {
                modelContext.insert(
                    UpNextQueueItemRecord(
                        episodeID: item.episodeID,
                        podcastID: item.podcastID,
                        sequence: item.sequence,
                        enqueuedAt: item.enqueuedAt,
                        sourcePlaylistID: item.sourcePlaylistID
                    )
                )
            }
            try saveModelContext(modelContext)
            didMutate()
            return true
        } catch {
            modelContext.rollback()
            items = previousItems
            lastErrorMessage = "Unable to save the rest of the playlist: \(error.localizedDescription)"
            return false
        }
    }

    private func persistCurrentOrder(modelContext: ModelContext) throws {
        let records = try modelContext.fetch(FetchDescriptor<UpNextQueueItemRecord>())
        var recordsByEpisodeID = Dictionary(grouping: records, by: \.episodeID)

        for item in items {
            guard let matches = recordsByEpisodeID.removeValue(forKey: item.episodeID),
                  let record = matches.first
            else {
                modelContext.insert(
                    UpNextQueueItemRecord(
                        episodeID: item.episodeID,
                        podcastID: item.podcastID,
                        sequence: item.sequence,
                        enqueuedAt: item.enqueuedAt,
                        sourcePlaylistID: item.sourcePlaylistID
                    )
                )
                continue
            }

            record.sequence = item.sequence
            if record.sourcePlaylistID != item.sourcePlaylistID {
                record.sourcePlaylistID = item.sourcePlaylistID
            }
            for duplicate in matches.dropFirst() {
                modelContext.delete(duplicate)
            }
        }

        for orphanedRecords in recordsByEpisodeID.values {
            for record in orphanedRecords {
                modelContext.delete(record)
            }
        }
        try saveModelContext(modelContext)
    }

    private func deleteRecords(episodeID: String, modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<UpNextQueueItemRecord>(
            predicate: #Predicate { $0.episodeID == episodeID }
        )
        for record in try modelContext.fetch(descriptor) {
            modelContext.delete(record)
        }
    }

    private func renumberItems() {
        for index in items.indices {
            items[index].sequence = index
        }
    }

    private func didMutate() {
        lastErrorMessage = nil
        onQueueChanged?()
    }

    private static func item(
        from record: UpNextQueueItemRecord,
        sequence: Int
    ) -> UpNextQueueItem {
        UpNextQueueItem(
            episodeID: record.episodeID,
            podcastID: record.podcastID,
            sequence: sequence,
            enqueuedAt: record.enqueuedAt,
            sourcePlaylistID: record.sourcePlaylistID
        )
    }
}
