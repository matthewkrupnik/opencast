import Foundation
import Observation
import OpenCastCore
import SwiftData

/// Owns the synced playlists with `UpNextQueueStore`'s save and rollback
/// mechanics. Every playlist is a saved rule. Item rows, from the retired
/// hand-picked playlists, still load, sync and repair with their playlists,
/// but nothing adds to them. Every save dirties a playlist, item or playlist tombstone row, because it
/// carries a self-save credit that would otherwise swallow a remote change.
@Observable
final class PlaylistStore {
    private typealias ListedState = (
        playlists: [PlaylistSummary],
        itemsByPlaylistID: [String: [PlaylistItem]],
        needsRepair: Bool
    )

    private(set) var playlists: [PlaylistSummary] = []
    private(set) var itemsByPlaylistID: [String: [PlaylistItem]] = [:]
    private(set) var lastErrorMessage: String?
    var sortOrder: PlaylistSortOrder = .recentlyUpdated {
        didSet {
            guard sortOrder != oldValue else {
                return
            }
            playlists = Self.sorted(playlists, by: sortOrder)
        }
    }

    @ObservationIgnored var onPlaylistsChanged: (() -> Void)?
    /// Smart playlist evaluations, keyed by the tokens each rule reads; the
    /// app model fills it and this store drops entries with their playlists.
    @ObservationIgnored let smartEvaluations = SmartPlaylistEvaluationCache()
    @ObservationIgnored private let saveSyncedStore: (ModelContext) throws -> Void
    @ObservationIgnored private let now: () -> Date
    /// Re-keys staged by `migrateEpisodeSidecars` until the reconciliation
    /// reports whether its save committed.
    @ObservationIgnored private var stagedIdentityMigration: StagedIdentityMigration?

    /// `saveSyncedStore` is the synced-store save (the self-save ledger in the
    /// app); `now` is the test seam for deterministic timestamps.
    init(
        saveSyncedStore: @escaping (ModelContext) throws -> Void,
        now: @escaping () -> Date = { .now }
    ) {
        self.saveSyncedStore = saveSyncedStore
        self.now = now
    }

    static let defaultAllPlaylistID = "opencast-default-all"

    func load(modelContext: ModelContext) {
        stagedIdentityMigration = nil
        do {
            // A fixed ID lets duplicate repair fold the copy each device
            // creates into one, and a tombstone keeps a deleted one deleted.
            if try modelContext.fetchCount(FetchDescriptor<PlaylistRecord>()) == 0,
               try !PlaylistTombstoneIndex(modelContext.fetch(FetchDescriptor<PlaylistTombstoneRecord>()))
                .shadowsPlaylist(Self.defaultAllPlaylistID) {
                modelContext.insert(PlaylistRecord(
                    playlistID: Self.defaultAllPlaylistID,
                    name: "All",
                    kind: .smart,
                    // Every unplayed episode, newest first: the list the Inbox was.
                    ruleJSON: PlaylistRule(sortOrder: .newestFirst).encodedJSON(),
                    origin: .user
                ))
                try saveSyncedStore(modelContext)
            }
            let state = try fetchListedState(modelContext: modelContext)
            playlists = state.playlists
            itemsByPlaylistID = state.itemsByPlaylistID
            lastErrorMessage = nil
            onPlaylistsChanged?()
        } catch {
            modelContext.rollback()
            lastErrorMessage = "Unable to load playlists: \(error.localizedDescription)"
        }
    }

    /// Rereads the rows after something outside this store may have changed
    /// them (an import, a repair pass) and publishes only on a difference.
    ///
    /// It never rolls back or drops a staged re-key: it wrote nothing, and the
    /// context is shared with writers whose pending changes are not its own.
    /// The full fetch is deliberate, since an identity re-key and a feed-move
    /// rule rewrite leave `updatedAt` alone and a cheaper probe would miss them.
    @discardableResult
    func reload(modelContext: ModelContext) -> PlaylistReloadChange {
        let state: ListedState
        do {
            state = try fetchListedState(modelContext: modelContext)
        } catch {
            lastErrorMessage = "Unable to reload playlists: \(error.localizedDescription)"
            return PlaylistReloadChange()
        }

        var change = PlaylistReloadChange(needsRepair: state.needsRepair)
        // A playlist emptied in place keeps an empty entry in memory, while
        // the rows produce no entry at all; neither is a change.
        guard state.playlists != playlists
            || state.itemsByPlaylistID != itemsByPlaylistID.filter({ !$0.value.isEmpty })
        else {
            return change
        }

        let previousNames = Dictionary(
            playlists.map { ($0.playlistID, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        let currentNames = Dictionary(
            state.playlists.map { ($0.playlistID, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        change.didChange = true
        change.removedPlaylistIDs = Set(previousNames.keys).subtracting(currentNames.keys)
        change.renamedPlaylistIDs = Set(
            currentNames.compactMap { playlistID, name in
                guard let previousName = previousNames[playlistID], previousName != name else {
                    return nil
                }
                return playlistID
            }
        )

        playlists = state.playlists
        itemsByPlaylistID = state.itemsByPlaylistID
        for playlistID in change.removedPlaylistIDs {
            smartEvaluations.remove(playlistID)
        }
        onPlaylistsChanged?()
        return change
    }

    /// Stores `rule`, or the default rule without one.
    @discardableResult
    func create(
        name: String,
        rule: PlaylistRule? = nil,
        origin: PlaylistOrigin = .user,
        modelContext: ModelContext
    ) -> PlaylistSummary? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastErrorMessage = "Unable to create the playlist: enter a name."
            return nil
        }

        let timestamp = now()
        let tintKey = PlaylistTint.next(after: playlists.compactMap(\.tintKey)).rawValue
        let record = PlaylistRecord(
            name: trimmedName,
            kind: .smart,
            ruleJSON: (rule ?? .default).normalized().encodedJSON(),
            tintKey: tintKey,
            origin: origin,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let summary = Self.summary(from: record, items: [])
        let previousPlaylists = playlists
        playlists = Self.sorted(playlists + [summary], by: sortOrder)

        do {
            modelContext.insert(record)
            try saveSyncedStore(modelContext)
            didMutate()
            return summary
        } catch {
            modelContext.rollback()
            playlists = previousPlaylists
            lastErrorMessage = "Unable to create the playlist: \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func rename(_ playlistID: String, to name: String, modelContext: ModelContext) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastErrorMessage = "Unable to rename the playlist: enter a name."
            return false
        }

        return updatePlaylist(
            playlistID,
            failure: "Unable to rename the playlist",
            modelContext: modelContext
        ) { summary in
            summary.name = trimmedName
        }
    }

    /// Stores a smart playlist's rule in its canonical form; an identical
    /// rule is a no-op. A rule this build cannot read is never overwritten,
    /// so an older app cannot clobber a newer version's rule.
    @discardableResult
    func setRule(
        _ rule: PlaylistRule,
        for playlistID: String,
        modelContext: ModelContext
    ) -> Bool {
        let failure = "Unable to update the playlist rules"
        guard let current = playlists.first(where: { $0.playlistID == playlistID }) else {
            lastErrorMessage = "\(failure) because the playlist no longer exists."
            return false
        }
        guard current.kind == .smart else {
            lastErrorMessage = "\(failure)."
            return false
        }
        guard !current.hasUnreadableRule else {
            lastErrorMessage = "These rules need a newer version of the app."
            return false
        }

        // Decided on the decoded rule: a row stored without JSON, or in a
        // non-canonical encoding, must not save and bump for a re-picked value.
        let normalizedRule = rule.normalized()
        guard normalizedRule != current.rule else {
            return true
        }
        return updatePlaylist(
            playlistID,
            failure: failure,
            modelContext: modelContext
        ) { summary in
            summary.rule = normalizedRule
            summary.ruleJSON = normalizedRule.encodedJSON()
        }
    }

    @discardableResult
    func delete(_ playlistID: String, modelContext: ModelContext) -> Bool {
        let previousPlaylists = playlists
        let previousItems = itemsByPlaylistID

        do {
            let playlistRecords = try fetchPlaylistRecords(playlistID, modelContext: modelContext)
            let itemRecords = try fetchItemRecords(playlistID, modelContext: modelContext)
            let deletesLoadedState = playlists.contains { $0.playlistID == playlistID }
                || itemsByPlaylistID[playlistID] != nil
            guard deletesLoadedState || !playlistRecords.isEmpty || !itemRecords.isEmpty else {
                return true
            }

            playlists.removeAll { $0.playlistID == playlistID }
            itemsByPlaylistID[playlistID] = nil
            for record in itemRecords {
                modelContext.delete(record)
            }
            for record in playlistRecords {
                modelContext.delete(record)
            }
            // Inserted even when memory listed the playlist and no row was
            // left: another device may still hold rows, and the tombstone is
            // what keeps the delete from being undone when they sync back.
            modelContext.insert(PlaylistTombstoneRecord(playlistID: playlistID, deletedAt: now()))
            try saveSyncedStore(modelContext)
            smartEvaluations.remove(playlistID)
            didMutate()
            return true
        } catch {
            modelContext.rollback()
            playlists = previousPlaylists
            itemsByPlaylistID = previousItems
            lastErrorMessage = "Unable to delete the playlist: \(error.localizedDescription)"
            return false
        }
    }

    func resetAfterDataNuke() {
        playlists = []
        itemsByPlaylistID = [:]
        smartEvaluations.removeAll()
        stagedIdentityMigration = nil
        lastErrorMessage = nil
        onPlaylistsChanged?()
    }

    func consumeLastErrorMessage() -> String? {
        defer { lastErrorMessage = nil }
        return lastErrorMessage
    }

    private func updatePlaylist(
        _ playlistID: String,
        failure: String,
        modelContext: ModelContext,
        change: (inout PlaylistSummary) -> Void
    ) -> Bool {
        guard let index = playlists.firstIndex(where: { $0.playlistID == playlistID }) else {
            lastErrorMessage = "\(failure) because the playlist no longer exists."
            return false
        }

        var updatedSummary = playlists[index]
        change(&updatedSummary)
        guard updatedSummary != playlists[index] else {
            return true
        }

        let previousPlaylists = playlists

        do {
            let records = try fetchPlaylistRecords(playlistID, modelContext: modelContext)
            guard !records.isEmpty else {
                lastErrorMessage = "\(failure) because the playlist no longer exists."
                return false
            }

            updatedSummary.updatedAt = now()
            for record in records {
                record.name = updatedSummary.name
                record.ruleJSON = updatedSummary.ruleJSON
                record.hidesPlayed = updatedSummary.hidesPlayed
                record.updatedAt = updatedSummary.updatedAt
            }
            playlists[index] = updatedSummary
            playlists = Self.sorted(playlists, by: sortOrder)
            try saveSyncedStore(modelContext)
            didMutate()
            return true
        } catch {
            modelContext.rollback()
            playlists = previousPlaylists
            lastErrorMessage = "\(failure): \(error.localizedDescription)"
            return false
        }
    }

    private func fetchPlaylistRecords(
        _ playlistID: String,
        modelContext: ModelContext
    ) throws -> [PlaylistRecord] {
        let targetPlaylistID = playlistID
        return try modelContext.fetch(
            FetchDescriptor<PlaylistRecord>(
                predicate: #Predicate { record in
                    record.playlistID == targetPlaylistID
                }
            )
        )
    }

    private func fetchItemRecords(
        _ playlistID: String,
        modelContext: ModelContext
    ) throws -> [PlaylistItemRecord] {
        let targetPlaylistID = playlistID
        return try modelContext.fetch(
            FetchDescriptor<PlaylistItemRecord>(
                predicate: #Predicate { record in
                    record.playlistID == targetPlaylistID
                },
                sortBy: Self.itemSortDescriptors
            )
        )
    }

    /// Both tables in full: they are small, and memory must match every row.
    private func fetchListedState(modelContext: ModelContext) throws -> ListedState {
        let listed = try listedRows(
            playlistRecords: modelContext.fetch(FetchDescriptor<PlaylistRecord>()),
            itemRecords: modelContext.fetch(
                FetchDescriptor<PlaylistItemRecord>(sortBy: Self.itemSortDescriptors)
            ),
            modelContext: modelContext
        )
        let itemsByID = Dictionary(grouping: listed.items.map { Self.item(from: $0) }, by: \.playlistID)
        let summaries = listed.playlists.map { record in
            Self.summary(from: record, items: itemsByID[record.playlistID] ?? [])
        }
        return (Self.sorted(summaries, by: sortOrder), itemsByID, listed.needsRepair)
    }

    /// The rows a duplicate repair pass would keep, found without changing
    /// the store, so memory never lists a twin or a tombstoned row that the
    /// next pass deletes, and a mutation never rewrites one. Twin groups and
    /// tombstones follow `PlaylistSyncRepairer`: one row per `playlistID` and
    /// per (`playlistID`, `episodeID`), the smallest `dedupeUUID` winning for
    /// playlists and the newest `addedAt` for items, and rows with an empty
    /// key standing alone. `itemRecords` arrive in the
    /// store's item order and keep it. An item whose playlist is not listed is
    /// left out: repair never deletes it, and it reappears once its playlist
    /// row syncs in.
    private func listedRows(
        playlistRecords: [PlaylistRecord],
        itemRecords: [PlaylistItemRecord],
        modelContext: ModelContext
    ) throws -> (playlists: [PlaylistRecord], items: [PlaylistItemRecord], needsRepair: Bool) {
        let tombstones = PlaylistTombstoneIndex(
            try modelContext.fetch(FetchDescriptor<PlaylistTombstoneRecord>())
        )
        var needsRepair = false

        var listedPlaylists: [PlaylistRecord] = []
        var playlistGroups: [String: [PlaylistRecord]] = [:]
        for record in playlistRecords {
            if tombstones.shadowsPlaylist(record.playlistID) {
                needsRepair = true
            } else if record.playlistID.isEmpty {
                listedPlaylists.append(record)
            } else {
                playlistGroups[record.playlistID, default: []].append(record)
            }
        }
        for group in playlistGroups.values {
            needsRepair = needsRepair || group.count > 1
            if let keep = Self.listedPlaylist(in: group) {
                listedPlaylists.append(keep)
            }
        }

        var survivingItems: [PlaylistItemRecord] = []
        var itemGroups: [PlaylistTombstoneIndex.ItemKey: [PlaylistItemRecord]] = [:]
        for record in itemRecords {
            guard !tombstones.shadowsItem(
                playlistID: record.playlistID,
                episodeID: record.episodeID,
                addedAt: record.addedAt
            ) else {
                needsRepair = true
                continue
            }
            survivingItems.append(record)
            guard !record.playlistID.isEmpty, !record.episodeID.isEmpty else {
                continue
            }
            let key = PlaylistTombstoneIndex.ItemKey(
                playlistID: record.playlistID,
                episodeID: record.episodeID
            )
            itemGroups[key, default: []].append(record)
        }
        var unlistedItems: Set<ObjectIdentifier> = []
        for group in itemGroups.values where group.count > 1 {
            needsRepair = true
            let keep = Self.listedItem(in: group)
            for record in group where record !== keep {
                unlistedItems.insert(ObjectIdentifier(record))
            }
        }

        let listedPlaylistIDs = Set(listedPlaylists.map(\.playlistID))
        let listedItems = survivingItems.filter { record in
            listedPlaylistIDs.contains(record.playlistID)
                && !unlistedItems.contains(ObjectIdentifier(record))
        }
        return (listedPlaylists, listedItems, needsRepair)
    }

    /// The copy `PlaylistSyncRepairer` keeps, or, when no copy carries an
    /// identity, the freshest copy, whose content its fresh row carries.
    private static func listedPlaylist(in group: [PlaylistRecord]) -> PlaylistRecord? {
        PlaylistSyncRepairer.keptPlaylist(in: group)
            ?? group.min(by: PlaylistSyncRepairer.isFresherPlaylist)
    }

    private static func listedItem(in group: [PlaylistItemRecord]) -> PlaylistItemRecord? {
        PlaylistSyncRepairer.keptItem(in: group)
            ?? group.min(by: PlaylistSyncRepairer.isFresherItem)
    }

    private func didMutate() {
        lastErrorMessage = nil
        onPlaylistsChanged?()
    }

    /// Keys are plain-`String` ordered; the default `.localizedStandard`
    /// comparator is numeric-aware and would misorder them.
    private static var itemSortDescriptors: [SortDescriptor<PlaylistItemRecord>] {
        [
            SortDescriptor(\.sortKey, comparator: .lexical),
            SortDescriptor(\.addedAt),
            SortDescriptor(\.itemID, comparator: .lexical)
        ]
    }

    private static func sorted(
        _ playlists: [PlaylistSummary],
        by order: PlaylistSortOrder
    ) -> [PlaylistSummary] {
        playlists.sorted { lhs, rhs in
            switch order {
            case .name:
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
            case .recentlyUpdated:
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
            }
            return lhs.playlistID < rhs.playlistID
        }
    }

    private static func summary(
        from record: PlaylistRecord,
        items: [PlaylistItem]
    ) -> PlaylistSummary {
        PlaylistSummary(
            playlistID: record.playlistID,
            name: record.name,
            kind: record.kind,
            ruleJSON: record.ruleJSON,
            rule: rule(for: record),
            hidesPlayed: record.hidesPlayed,
            tintKey: record.tintKey,
            origin: record.origin,
            itemCount: items.count,
            totalDuration: totalDuration(of: items),
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            coverPodcastIDs: coverPodcastIDs(for: items)
        )
    }

    /// A smart row without stored JSON reads as the default rule; only a
    /// stored rule that fails to decode is unreadable.
    private static func rule(for record: PlaylistRecord) -> PlaylistRule? {
        guard record.kind == .smart else {
            return nil
        }
        guard let ruleJSON = record.ruleJSON else {
            return .default
        }
        return PlaylistRule.decode(ruleJSON)
    }

    private static func summary(
        _ summary: PlaylistSummary,
        items: [PlaylistItem]
    ) -> PlaylistSummary {
        var updatedSummary = summary
        updatedSummary.itemCount = items.count
        updatedSummary.totalDuration = totalDuration(of: items)
        updatedSummary.coverPodcastIDs = coverPodcastIDs(for: items)
        return updatedSummary
    }

    private static func totalDuration(of items: [PlaylistItem]) -> TimeInterval {
        items.reduce(0) { total, item in
            total + (item.duration ?? 0)
        }
    }

    private static func coverPodcastIDs(for items: [PlaylistItem]) -> [String] {
        var podcastIDs: [String] = []
        for item in items where !podcastIDs.contains(item.podcastID) {
            podcastIDs.append(item.podcastID)
            if podcastIDs.count == 4 {
                break
            }
        }
        return podcastIDs
    }

    private static func item(from record: PlaylistItemRecord) -> PlaylistItem {
        PlaylistItem(
            itemID: record.itemID,
            playlistID: record.playlistID,
            episodeID: record.episodeID,
            podcastID: record.podcastID,
            sortKey: record.sortKey,
            addedAt: record.addedAt,
            updatedAt: record.updatedAt,
            episodeTitle: record.episodeTitle,
            podcastTitle: record.podcastTitle,
            artworkURL: record.artworkURL,
            audioURL: record.audioURL,
            duration: record.duration,
            publishedAt: record.publishedAt
        )
    }

    private static func item(
        _ item: PlaylistItem,
        episodeID: String,
        podcastID: String
    ) -> PlaylistItem {
        PlaylistItem(
            itemID: item.itemID,
            playlistID: item.playlistID,
            episodeID: episodeID,
            podcastID: podcastID,
            sortKey: item.sortKey,
            addedAt: item.addedAt,
            updatedAt: item.updatedAt,
            episodeTitle: item.episodeTitle,
            podcastTitle: item.podcastTitle,
            artworkURL: item.artworkURL,
            audioURL: item.audioURL,
            duration: item.duration,
            publishedAt: item.publishedAt
        )
    }
}

extension PlaylistStore: EpisodeIdentitySidecarMigrating {
    /// Stages the loaded items' re-key for the rows
    /// `EpisodeIdentityMigrationApplier` rewrites in the same pass. Memory
    /// only: the applier owns the rows and the save, and the staged state
    /// is published by `finishEpisodeSidecarMigration` only once that save
    /// has committed, so memory never runs ahead of storage. The collision
    /// rule is the applier's, per playlist: a successor already present
    /// drops the departed item instead of leaving two members for one
    /// episode.
    func migrateEpisodeSidecars(
        from oldEpisodeID: String,
        to newEpisodeID: String,
        canonicalPodcastID: String,
        modelContext: ModelContext
    ) throws {
        var staged = stagedIdentityMigration
            ?? StagedIdentityMigration(playlists: playlists, itemsByPlaylistID: itemsByPlaylistID)
        for (playlistID, items) in staged.itemsByPlaylistID
            where items.contains(where: { $0.episodeID == oldEpisodeID }) {
            let hasSuccessor = items.contains { $0.episodeID == newEpisodeID }
            var didRekey = false
            var migratedItems: [PlaylistItem] = []
            migratedItems.reserveCapacity(items.count)
            for item in items {
                guard item.episodeID == oldEpisodeID else {
                    migratedItems.append(item)
                    continue
                }
                guard !hasSuccessor, !didRekey else {
                    continue
                }
                migratedItems.append(Self.item(item, episodeID: newEpisodeID, podcastID: canonicalPodcastID))
                didRekey = true
            }
            staged.itemsByPlaylistID[playlistID] = migratedItems
            if let index = staged.playlists.firstIndex(where: { $0.playlistID == playlistID }) {
                staged.playlists[index] = Self.summary(staged.playlists[index], items: migratedItems)
            }
            staged.didChange = true
        }
        stagedIdentityMigration = staged
    }

    /// A smart rule names its shows by feed URL, so a moved subscription's
    /// URL is swapped in every rule that lists it; otherwise the show would
    /// silently drop out of the rule. Rows and loaded summaries follow the
    /// episode re-key's staging, and `updatedAt` is untouched because a
    /// re-key is not an edit. A rule this build cannot read is left alone.
    func migrateFeedSidecars(
        from oldCanonicalFeedURL: String,
        to newCanonicalFeedURL: String,
        modelContext: ModelContext
    ) throws {
        func isMoved(_ podcastID: String) -> Bool {
            URLCanonicalizer.canonicalString(forRawString: podcastID) == oldCanonicalFeedURL
        }

        for record in try modelContext.fetch(FetchDescriptor<PlaylistRecord>()) where record.kind == .smart {
            guard let migratedRule = PlaylistRule.decode(record.ruleJSON)?
                .replacingPodcastIDs(where: isMoved, with: newCanonicalFeedURL)
            else {
                continue
            }
            record.ruleJSON = migratedRule.encodedJSON()
        }

        var staged = stagedIdentityMigration
            ?? StagedIdentityMigration(playlists: playlists, itemsByPlaylistID: itemsByPlaylistID)
        for index in staged.playlists.indices {
            guard let migratedRule = staged.playlists[index].rule?
                .replacingPodcastIDs(where: isMoved, with: newCanonicalFeedURL)
            else {
                continue
            }
            staged.playlists[index].rule = migratedRule
            staged.playlists[index].ruleJSON = migratedRule.encodedJSON()
            staged.didChange = true
        }
        stagedIdentityMigration = staged
    }

    func finishEpisodeSidecarMigration(committed: Bool) {
        guard let staged = stagedIdentityMigration else {
            return
        }
        stagedIdentityMigration = nil
        guard committed, staged.didChange else {
            return
        }
        itemsByPlaylistID = staged.itemsByPlaylistID
        playlists = Self.sorted(staged.playlists, by: sortOrder)
        onPlaylistsChanged?()
    }
}

/// The loaded state with a reconciliation's re-keys applied, held back until
/// the reconciliation's save commits.
private struct StagedIdentityMigration {
    var playlists: [PlaylistSummary]
    var itemsByPlaylistID: [String: [PlaylistItem]]
    var didChange = false
}
