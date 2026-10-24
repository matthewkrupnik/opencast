import Foundation
import SwiftData
import Testing
@testable import OpenCast

@MainActor
@Suite("Playlist store")
struct PlaylistStoreTests {
    @Test("Create, rename and delete persist, and delete removes the playlist's items")
    func createRenameDelete() throws {
        let fixture = try makeFixture()
        let commute = try #require(
            fixture.store.create(name: "  Commute  ", modelContext: fixture.context)
        )
        let other = try #require(
            fixture.store.create(name: "Other", modelContext: fixture.context)
        )
        #expect(commute.name == "Commute")
        #expect(commute.kind == .smart)
        #expect(commute.origin == .user)
        #expect(commute.tintKey != nil)
        try seedItems([episode("a"), episode("b")], in: commute.playlistID, fixture: fixture)
        try seedItems([episode("a")], in: other.playlistID, fixture: fixture)

        #expect(fixture.store.rename(commute.playlistID, to: "Morning", modelContext: fixture.context))
        #expect(!fixture.store.rename(commute.playlistID, to: "   ", modelContext: fixture.context))
        #expect(fixture.store.lastErrorMessage?.contains("Unable to rename the playlist") == true)

        let renamedContext = ModelContext(fixture.container)
        let renamedRecords = try storedPlaylists(in: renamedContext)
        #expect(fixture.store.playlists.first(where: { $0.playlistID == commute.playlistID })?.name == "Morning")
        #expect(renamedRecords.first(where: { $0.playlistID == commute.playlistID })?.name == "Morning")

        #expect(fixture.store.delete(commute.playlistID, modelContext: fixture.context))

        let deletedContext = ModelContext(fixture.container)
        #expect(fixture.store.playlists.map(\.playlistID) == [other.playlistID])
        #expect(fixture.store.itemsByPlaylistID[commute.playlistID] == nil)
        #expect(fixture.store.lastErrorMessage == nil)
        #expect(try storedPlaylists(in: deletedContext).map(\.playlistID) == [other.playlistID])
        #expect(try storedItems(in: deletedContext).map(\.playlistID) == [other.playlistID])
    }

    @Test("A failed create leaves memory and storage unchanged")
    func createRollsBack() throws {
        let fixture = try makeFixture()
        let existing = try #require(
            fixture.store.create(name: "Existing", modelContext: fixture.context)
        )
        fixture.probe.failsSaves = true

        let created = fixture.store.create(name: "New", modelContext: fixture.context)

        let storedContext = ModelContext(fixture.container)
        #expect(created == nil)
        #expect(fixture.store.playlists.map(\.playlistID) == [existing.playlistID])
        #expect(try storedPlaylists(in: storedContext).map(\.playlistID) == [existing.playlistID])
        #expect(try fixture.context.fetch(FetchDescriptor<PlaylistRecord>()).count == 1)
        #expect(fixture.store.lastErrorMessage?.contains("Unable to create the playlist") == true)
    }

    @Test("A failed delete leaves memory and storage unchanged")
    func deleteRollsBack() throws {
        let fixture = try makeFixture()
        let playlist = try #require(
            fixture.store.create(name: "Commute", modelContext: fixture.context)
        )
        try seedItems(["a", "b"].map { episode($0) }, in: playlist.playlistID, fixture: fixture)
        let summaryBefore = fixture.store.playlists
        let itemsBefore = fixture.store.itemsByPlaylistID
        fixture.probe.failsSaves = true

        let deleted = fixture.store.delete(playlist.playlistID, modelContext: fixture.context)

        let storedContext = ModelContext(fixture.container)
        #expect(!deleted)
        #expect(fixture.store.playlists == summaryBefore)
        #expect(fixture.store.itemsByPlaylistID == itemsBefore)
        #expect(try storedPlaylists(in: storedContext).map(\.playlistID) == [playlist.playlistID])
        #expect(try storedItems(in: storedContext).map(\.episodeID) == ["a", "b"])
        #expect(try fixture.context.fetch(FetchDescriptor<PlaylistRecord>()).count == 1)
        #expect(try fixture.context.fetch(FetchDescriptor<PlaylistItemRecord>()).count == 2)
        #expect(fixture.store.lastErrorMessage?.contains("Unable to delete the playlist") == true)
    }

    @Test("An identity re-key is published only once its save commits and skips an unloaded store")
    func identityRekeyPublishesOnCommit() throws {
        let successorPodcastID = "https://example.com/new.xml"
        let unloaded = PlaylistStore(saveSyncedStore: SyncedStoreSelfSaveLedger().save)
        var unloadedChanges = 0
        unloaded.onPlaylistsChanged = { unloadedChanges += 1 }
        let unloadedContext = ModelContext(try OpenCastModelContainerFactory.make(inMemory: true))

        try unloaded.migrateEpisodeSidecars(
            from: "old",
            to: "new",
            canonicalPodcastID: successorPodcastID,
            modelContext: unloadedContext
        )
        unloaded.finishEpisodeSidecarMigration(committed: true)

        #expect(unloaded.playlists.isEmpty)
        #expect(unloaded.itemsByPlaylistID.isEmpty)
        #expect(unloadedChanges == 0)

        let fixture = try makeFixture()
        let departedOnly = try #require(
            fixture.store.create(name: "Departed Only", modelContext: fixture.context)
        )
        let both = try #require(
            fixture.store.create(name: "Both", modelContext: fixture.context)
        )
        try seedItems([episode("a"), episode("old")], in: departedOnly.playlistID, fixture: fixture)
        try seedItems([episode("old"), episode("new")], in: both.playlistID, fixture: fixture)
        let keysBefore = try storedKeysByItemID(in: fixture.container)
        let departedItemID = try #require(fixture.store.itemsByPlaylistID[departedOnly.playlistID]?.last?.itemID)
        let playlistsBefore = fixture.store.playlists
        let itemsBefore = fixture.store.itemsByPlaylistID
        let saveCountBefore = fixture.probe.saveCount
        var changeCount = 0
        fixture.store.onPlaylistsChanged = { changeCount += 1 }

        // A save that fails leaves the loaded state exactly as it was.
        try fixture.store.migrateEpisodeSidecars(
            from: "old",
            to: "new",
            canonicalPodcastID: successorPodcastID,
            modelContext: fixture.context
        )
        #expect(fixture.store.itemsByPlaylistID == itemsBefore)
        #expect(fixture.store.playlists == playlistsBefore)
        #expect(changeCount == 0)
        fixture.store.finishEpisodeSidecarMigration(committed: false)

        #expect(fixture.store.itemsByPlaylistID == itemsBefore)
        #expect(fixture.store.playlists == playlistsBefore)
        #expect(changeCount == 0)

        // A committed save publishes the re-key once.
        try fixture.store.migrateEpisodeSidecars(
            from: "old",
            to: "new",
            canonicalPodcastID: successorPodcastID,
            modelContext: fixture.context
        )
        #expect(fixture.store.itemsByPlaylistID == itemsBefore)
        #expect(changeCount == 0)
        fixture.store.finishEpisodeSidecarMigration(committed: true)

        #expect(changeCount == 1)
        #expect(fixture.probe.saveCount == saveCountBefore)
        let departedItems = fixture.store.itemsByPlaylistID[departedOnly.playlistID] ?? []
        #expect(departedItems.map(\.episodeID) == ["a", "new"])
        #expect(departedItems.last?.itemID == departedItemID)
        #expect(departedItems.last?.podcastID == successorPodcastID)
        #expect(departedItems.last?.sortKey == keysBefore[departedItemID])
        #expect(fixture.store.itemsByPlaylistID[both.playlistID]?.map(\.episodeID) == ["new"])
        let departedSummary = try #require(
            fixture.store.playlists.first(where: { $0.playlistID == departedOnly.playlistID })
        )
        let bothSummary = try #require(fixture.store.playlists.first(where: { $0.playlistID == both.playlistID }))
        #expect(departedSummary.itemCount == 2)
        #expect(departedSummary.coverPodcastIDs == ["https://example.com/feed.xml", successorPodcastID])
        #expect(bothSummary.itemCount == 1)
        #expect(bothSummary.totalDuration == 60)
        #expect(fixture.store.playlists.map(\.updatedAt) == playlistsBefore.map(\.updatedAt))
        // Rows belong to the applier; the memory pass leaves them alone.
        #expect(
            try storedItems(in: ModelContext(fixture.container)).map(\.episodeID).sorted()
                == ["a", "new", "old", "old"]
        )

        // Nothing staged: a stray completion is a no-op, and a re-key that
        // changes nothing stays quiet.
        fixture.store.finishEpisodeSidecarMigration(committed: true)
        try fixture.store.migrateEpisodeSidecars(
            from: "old",
            to: "new",
            canonicalPodcastID: successorPodcastID,
            modelContext: fixture.context
        )
        fixture.store.finishEpisodeSidecarMigration(committed: true)

        #expect(changeCount == 1)
    }

    @Test("A failed playlist update keeps the loaded summary")
    func updateRollsBack() throws {
        let fixture = try makeFixture()
        let playlist = try #require(
            fixture.store.create(name: "Commute", modelContext: fixture.context)
        )
        fixture.probe.failsSaves = true

        #expect(!fixture.store.rename(playlist.playlistID, to: "Evening", modelContext: fixture.context))

        let storedContext = ModelContext(fixture.container)
        #expect(fixture.store.playlists == [playlist])
        #expect(try storedPlaylists(in: storedContext).first?.name == "Commute")
        #expect(fixture.store.lastErrorMessage?.contains("Unable to rename the playlist") == true)
    }

    @Test("Sort order switches between name and most recently updated")
    func sortOrders() throws {
        let fixture = try makeFixture()
        let beta = try #require(fixture.store.create(name: "Beta", modelContext: fixture.context))
        _ = try #require(fixture.store.create(name: "alpha", modelContext: fixture.context))
        _ = try #require(fixture.store.create(name: "Gamma", modelContext: fixture.context))

        #expect(fixture.store.sortOrder == .recentlyUpdated)
        #expect(fixture.store.playlists.map(\.name) == ["Gamma", "alpha", "Beta"])

        fixture.store.sortOrder = .name
        #expect(fixture.store.playlists.map(\.name) == ["alpha", "Beta", "Gamma"])

        #expect(fixture.store.setRule(PlaylistRule(status: .played), for: beta.playlistID, modelContext: fixture.context))
        #expect(fixture.store.playlists.map(\.name) == ["alpha", "Beta", "Gamma"])

        fixture.store.sortOrder = .recentlyUpdated
        #expect(fixture.store.playlists.map(\.name) == ["Beta", "Gamma", "alpha"])
    }

    @Test("Every mutation bumps the playlist's updatedAt")
    func mutationsBumpUpdatedAt() throws {
        let fixture = try makeFixture()
        let playlist = try #require(
            fixture.store.create(name: "Commute", modelContext: fixture.context)
        )
        var updatedAt = playlist.updatedAt

        #expect(fixture.store.rename(playlist.playlistID, to: "Evening", modelContext: fixture.context))
        updatedAt = try expectBumpedUpdatedAt(playlist.playlistID, since: updatedAt, fixture: fixture)
        var playedRule = PlaylistRule.default
        playedRule.status = .played
        let didSetRule = fixture.store.setRule(playedRule, for: playlist.playlistID, modelContext: fixture.context)
        #expect(didSetRule)
        _ = try expectBumpedUpdatedAt(playlist.playlistID, since: updatedAt, fixture: fixture)

        let storedContext = ModelContext(fixture.container)
        let storedRecords = try storedPlaylists(in: storedContext)
        let storedSmart = try #require(storedRecords.first(where: { $0.playlistID == playlist.playlistID }))
        #expect(storedSmart.name == "Evening")
        #expect(storedSmart.ruleJSON == playedRule.encodedJSON())
    }

    @Test("Playlists take the least-used tint")
    func smartPlaylistsTakeLeastUsedTint() throws {
        let fixture = try makeFixture()
        let first = try #require(fixture.store.create(name: "One", modelContext: fixture.context))
        let second = try #require(fixture.store.create(name: "Two", modelContext: fixture.context))
        let third = try #require(
            fixture.store.create(name: "Three", origin: .ai, modelContext: fixture.context)
        )

        #expect(
            [first, second, third].map(\.tintKey) == [
                PlaylistTint.red.rawValue,
                PlaylistTint.orange.rawValue,
                PlaylistTint.yellow.rawValue
            ]
        )
        #expect(first.ruleJSON == PlaylistRule.default.encodedJSON())
        #expect(first.rule == .default)
        #expect(third.origin == .ai)

        #expect(fixture.store.delete(second.playlistID, modelContext: fixture.context))
        let fourth = try #require(fixture.store.create(name: "Four", modelContext: fixture.context))
        #expect(fourth.tintKey == PlaylistTint.orange.rawValue)

        let storedContext = ModelContext(fixture.container)
        let storedRecords = try storedPlaylists(in: storedContext)
        let storedFourth = try #require(storedRecords.first(where: { $0.playlistID == fourth.playlistID }))
        #expect(storedFourth.kind == .smart)
        #expect(storedFourth.tintKey == PlaylistTint.orange.rawValue)
    }

    @Test("A smart create stores the default rule and the first eight take distinct tints in case order")
    func smartCreateStoresDefaultRuleAndDistinctTints() throws {
        let fixture = try makeFixture()
        var created: [PlaylistSummary] = []
        for index in 1 ... PlaylistTint.allCases.count {
            let summary = try #require(
                fixture.store.create(name: "Smart \(index)", modelContext: fixture.context)
            )
            created.append(summary)
        }
        let ninth = try #require(fixture.store.create(name: "Smart 9", modelContext: fixture.context))

        #expect(created.map(\.tintKey) == PlaylistTint.allCases.map(\.rawValue))
        #expect(created.compactMap(\.tint) == PlaylistTint.allCases)
        #expect(ninth.tint == .red)
        #expect(created.allSatisfy { $0.ruleJSON == PlaylistRule.default.encodedJSON() })
        #expect(created.allSatisfy { $0.rule == .default && !$0.hasUnreadableRule })
        let storedRecords = try storedPlaylists(in: ModelContext(fixture.container))
        #expect(storedRecords.count == 9)
        #expect(storedRecords.allSatisfy { $0.ruleJSON == PlaylistRule.default.encodedJSON() })
        let reloaded = PlaylistStore(saveSyncedStore: SyncedStoreSelfSaveLedger().save)
        reloaded.load(modelContext: ModelContext(fixture.container))
        #expect(reloaded.playlists.count == 9)
        #expect(reloaded.playlists.allSatisfy { $0.rule == .default })
    }

    @Test("A create stores the given rule normalized")
    func createStoresGivenRuleNormalized() throws {
        let fixture = try makeFixture()
        let rule = PlaylistRule(podcastIDs: [], status: .played, maximumAgeDays: -1, sortOrder: .longestFirst, limit: 50)
        let smart = try #require(
            fixture.store.create(name: "Smart", rule: rule, modelContext: fixture.context)
        )

        #expect(smart.rule == rule.normalized())
        #expect(smart.rule?.podcastIDs == nil)
        #expect(smart.rule?.maximumAgeDays == nil)
        #expect(smart.rule?.status == .played)
        #expect(smart.rule?.sortOrder == .oldestFirst)
        #expect(smart.ruleJSON == rule.normalized().encodedJSON())
        let storedRecords = try storedPlaylists(in: ModelContext(fixture.container))
        #expect(storedRecords.map(\.ruleJSON) == [rule.normalized().encodedJSON()])
    }

    @Test("Setting a rule stores its canonical form, bumps updatedAt, and saves and notifies once")
    func setRulePersistsCanonicalRule() throws {
        let fixture = try makeFixture()
        let playlist = try #require(
            fixture.store.create(name: "Fresh", modelContext: fixture.context)
        )
        let saveCount = fixture.probe.saveCount
        var changeCount = 0
        fixture.store.onPlaylistsChanged = { changeCount += 1 }
        let rule = PlaylistRule(
            podcastIDs: ["https://example.com/b.xml", "https://example.com/a.xml", "https://example.com/b.xml"],
            status: .downloaded,
            maximumMinutes: 45,
            sortOrder: .shortestFirst,
            limit: 0
        )
        let expected = rule.normalized()

        let didSetRule = fixture.store.setRule(rule, for: playlist.playlistID, modelContext: fixture.context)

        #expect(didSetRule)
        #expect(expected.podcastIDs == ["https://example.com/b.xml", "https://example.com/a.xml"])
        #expect(expected.sortOrder == .oldestFirst)
        #expect(expected.status == .all)
        #expect(expected.downloadedOnly)
        #expect(expected.limit == nil)
        let summary = try #require(fixture.store.playlists.first(where: { $0.playlistID == playlist.playlistID }))
        #expect(summary.rule == expected)
        #expect(summary.ruleJSON == expected.encodedJSON())
        _ = try expectBumpedUpdatedAt(playlist.playlistID, since: playlist.updatedAt, fixture: fixture)
        #expect(fixture.probe.saveCount == saveCount + 1)
        #expect(changeCount == 1)
        #expect(fixture.store.lastErrorMessage == nil)
        let stored = try #require(try storedPlaylists(in: ModelContext(fixture.container)).first)
        #expect(stored.ruleJSON == expected.encodedJSON())
        let reloaded = PlaylistStore(saveSyncedStore: SyncedStoreSelfSaveLedger().save)
        reloaded.load(modelContext: ModelContext(fixture.container))
        #expect(reloaded.playlists.first?.rule == expected)
    }

    @Test("Setting an identical rule, or one that normalizes to it, saves nothing and does not notify")
    func setIdenticalRuleIsNoOp() throws {
        let fixture = try makeFixture()
        let playlist = try #require(
            fixture.store.create(name: "Fresh", modelContext: fixture.context)
        )
        let saveCount = fixture.probe.saveCount
        var changeCount = 0
        fixture.store.onPlaylistsChanged = { changeCount += 1 }
        var equivalent = PlaylistRule.default
        equivalent.podcastIDs = []

        let setDefault = fixture.store.setRule(.default, for: playlist.playlistID, modelContext: fixture.context)
        let setEquivalent = fixture.store.setRule(equivalent, for: playlist.playlistID, modelContext: fixture.context)

        #expect(setDefault)
        #expect(setEquivalent)
        #expect(fixture.probe.saveCount == saveCount)
        #expect(changeCount == 0)
        #expect(fixture.store.playlists == [playlist])
        #expect(fixture.store.lastErrorMessage == nil)
    }

    @Test("Re-picking the rule a smart row without rule JSON already reads as saves nothing")
    func setRuleOnNilJSONRowIsNoOp() throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let updatedAt = Date(timeIntervalSince1970: 1_775_000_000)
        context.insert(
            PlaylistRecord(
                playlistID: "smart-nil",
                name: "Smart",
                kind: .smart,
                ruleJSON: nil,
                createdAt: updatedAt,
                updatedAt: updatedAt
            )
        )
        try context.save()
        var saveCount = 0
        let store = PlaylistStore(saveSyncedStore: SyncedStoreSelfSaveLedger(performSave: { modelContext in
            saveCount += 1
            try modelContext.save()
        }).save)
        store.load(modelContext: context)

        #expect(store.setRule(.default, for: "smart-nil", modelContext: context))
        #expect(saveCount == 0)
        #expect(store.playlists.first?.updatedAt == updatedAt)
        #expect(store.playlists.first?.ruleJSON == nil)
        #expect(store.lastErrorMessage == nil)
    }

    @Test("Setting a rule refuses a retired hand-picked playlist and a missing one without saving")
    func setRuleRefusesManualAndMissing() throws {
        let fixture = try makeFixture()
        fixture.context.insert(PlaylistRecord(playlistID: "manual", name: "Manual"))
        try fixture.context.save()
        fixture.store.reload(modelContext: fixture.context)
        let manual = try #require(fixture.store.playlists.first)
        let saveCount = fixture.probe.saveCount
        var changeCount = 0
        fixture.store.onPlaylistsChanged = { changeCount += 1 }

        let setManual = fixture.store.setRule(.default, for: manual.playlistID, modelContext: fixture.context)

        #expect(!setManual)
        #expect(fixture.store.lastErrorMessage == "Unable to update the playlist rules.")
        #expect(fixture.store.playlists == [manual])
        #expect(try storedPlaylists(in: ModelContext(fixture.container)).first?.ruleJSON == nil)

        let setMissing = fixture.store.setRule(.default, for: "missing", modelContext: fixture.context)

        #expect(!setMissing)
        #expect(
            fixture.store.lastErrorMessage
                == "Unable to update the playlist rules because the playlist no longer exists."
        )
        #expect(fixture.probe.saveCount == saveCount)
        #expect(changeCount == 0)
    }

    @Test("A newer-version rule loads as unreadable, refuses a new rule, and survives a rename verbatim")
    func unreadableRuleIsNeverOverwritten() throws {
        let fixture = try makeFixture()
        let newerRuleJSON = #"{"version":2,"clauses":[]}"#
        fixture.context.insert(
            PlaylistRecord(
                playlistID: "newer",
                name: "Newer",
                kind: .smart,
                ruleJSON: newerRuleJSON,
                tintKey: PlaylistTint.teal.rawValue
            )
        )
        try fixture.context.save()
        fixture.store.load(modelContext: fixture.context)
        let loaded = try #require(fixture.store.playlists.first)
        var changeCount = 0
        fixture.store.onPlaylistsChanged = { changeCount += 1 }

        #expect(loaded.rule == nil)
        #expect(loaded.hasUnreadableRule)
        #expect(loaded.ruleJSON == newerRuleJSON)
        #expect(loaded.tint == .teal)

        let didSetRule = fixture.store.setRule(.default, for: "newer", modelContext: fixture.context)

        #expect(!didSetRule)
        #expect(fixture.store.lastErrorMessage == "These rules need a newer version of the app.")
        #expect(fixture.probe.saveCount == 0)
        #expect(changeCount == 0)

        #expect(fixture.store.rename("newer", to: "Renamed", modelContext: fixture.context))

        let stored = try #require(try storedPlaylists(in: ModelContext(fixture.container)).first)
        #expect(stored.name == "Renamed")
        #expect(stored.ruleJSON == newerRuleJSON)
        #expect(fixture.store.playlists.first?.hasUnreadableRule == true)
    }

    @Test("A smart row without rule JSON reads as the default rule, malformed JSON is unreadable, and unknown tints read blue")
    func summaryRuleAndTintResolution() throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let createdAt = Date(timeIntervalSince1970: 1_775_000_000)
        let rows: [(playlistID: String, kind: PlaylistKind, ruleJSON: String?, tintKey: String?)] = [
            ("smart-nil", .smart, nil, nil),
            ("smart-malformed", .smart, "{", PlaylistTint.indigo.rawValue),
            ("smart-bare", .smart, #"{"version":1}"#, "sparkly"),
            ("manual", .manual, nil, PlaylistTint.red.rawValue)
        ]
        for (index, row) in rows.enumerated() {
            let timestamp = createdAt.addingTimeInterval(Double(index))
            context.insert(
                PlaylistRecord(
                    playlistID: row.playlistID,
                    name: row.playlistID,
                    kind: row.kind,
                    ruleJSON: row.ruleJSON,
                    tintKey: row.tintKey,
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            )
        }
        try context.save()
        let store = PlaylistStore(saveSyncedStore: SyncedStoreSelfSaveLedger().save)

        store.load(modelContext: context)

        let summaries = Dictionary(uniqueKeysWithValues: store.playlists.map { ($0.playlistID, $0) })
        let unset = try #require(summaries["smart-nil"])
        #expect(unset.rule == .default)
        #expect(!unset.hasUnreadableRule)
        #expect(unset.tint == .blue)
        let malformed = try #require(summaries["smart-malformed"])
        #expect(malformed.rule == nil)
        #expect(malformed.hasUnreadableRule)
        #expect(malformed.tint == .indigo)
        let bare = try #require(summaries["smart-bare"])
        #expect(bare.rule == PlaylistRule())
        #expect(!bare.hasUnreadableRule)
        #expect(bare.tint == .blue)
        let manual = try #require(summaries["manual"])
        #expect(manual.rule == nil)
        #expect(!manual.hasUnreadableRule)
        #expect(manual.tint == nil)
        #expect(PlaylistTint.resolved(nil) == .blue)
        #expect(PlaylistTint.resolved("sparkly") == .blue)
        #expect(PlaylistTint.allCases.allSatisfy { PlaylistTint.resolved($0.rawValue) == $0 })
    }

    @Test("Deleting a playlist drops only its memoized evaluation, and a failed delete keeps it")
    func deleteDropsMemoizedEvaluation() throws {
        let fixture = try makeFixture()
        let first = try #require(fixture.store.create(name: "First", modelContext: fixture.context))
        let second = try #require(fixture.store.create(name: "Second", modelContext: fixture.context))
        let cache = fixture.store.smartEvaluations
        let key = memoKey()
        _ = cache.evaluation(for: first.playlistID, key: key) { [episode("a")] }
        _ = cache.evaluation(for: second.playlistID, key: key) { [episode("b")] }
        #expect(cache.computeCount == 2)

        fixture.probe.failsSaves = true
        #expect(!fixture.store.delete(first.playlistID, modelContext: fixture.context))

        let kept = cache.evaluation(for: first.playlistID, key: key) { [] }
        #expect(kept.episodes.map(\.episodeID) == ["a"])
        #expect(cache.computeCount == 2)

        fixture.probe.failsSaves = false
        #expect(fixture.store.delete(first.playlistID, modelContext: fixture.context))

        let recomputed = cache.evaluation(for: first.playlistID, key: key) { [] }
        #expect(recomputed == .empty)
        #expect(cache.computeCount == 3)
        let untouched = cache.evaluation(for: second.playlistID, key: key) { [] }
        #expect(untouched.episodes.map(\.episodeID) == ["b"])
        #expect(cache.computeCount == 3)
    }

    @Test("A data nuke clears every memoized evaluation")
    func nukeClearsMemoizedEvaluations() throws {
        let fixture = try makeFixture()
        let first = try #require(fixture.store.create(name: "First", modelContext: fixture.context))
        let second = try #require(fixture.store.create(name: "Second", modelContext: fixture.context))
        let cache = fixture.store.smartEvaluations
        let key = memoKey()
        _ = cache.evaluation(for: first.playlistID, key: key) { [episode("a")] }
        _ = cache.evaluation(for: second.playlistID, key: key) { [episode("b")] }
        #expect(cache.computeCount == 2)

        fixture.store.resetAfterDataNuke()

        let firstAfter = cache.evaluation(for: first.playlistID, key: key) { [] }
        let secondAfter = cache.evaluation(for: second.playlistID, key: key) { [] }
        #expect(firstAfter == .empty)
        #expect(secondAfter == .empty)
        #expect(cache.computeCount == 4)
    }

    @Test("No-op mutations keep an unconsumed error and skip saves and notifications")
    func noOpMutationsStayHonest() throws {
        let fixture = try makeFixture()
        let playlist = try #require(
            fixture.store.create(name: "Commute", modelContext: fixture.context)
        )
        try seedItems([episode("a")], in: playlist.playlistID, fixture: fixture)
        var changeCount = 0
        fixture.store.onPlaylistsChanged = { changeCount += 1 }
        #expect(!fixture.store.rename(playlist.playlistID, to: " ", modelContext: fixture.context))
        let error = fixture.store.lastErrorMessage
        let saveCount = fixture.probe.saveCount
        let updatedAt = fixture.store.playlists.first?.updatedAt

        #expect(fixture.store.rename(playlist.playlistID, to: "Commute", modelContext: fixture.context))
        #expect(fixture.store.setRule(.default, for: playlist.playlistID, modelContext: fixture.context))
        #expect(fixture.store.delete("missing", modelContext: fixture.context))

        #expect(fixture.store.lastErrorMessage == error)
        #expect(error != nil)
        #expect(changeCount == 0)
        #expect(fixture.probe.saveCount == saveCount)
        #expect(fixture.store.playlists.first?.updatedAt == updatedAt)
    }

    @Test("Successful mutations notify once and failed saves do not notify")
    func successfulMutationsNotifyOnce() throws {
        let fixture = try makeFixture()
        var changeCount = 0
        fixture.store.onPlaylistsChanged = { changeCount += 1 }

        let playlist = try #require(
            fixture.store.create(name: "Commute", modelContext: fixture.context)
        )
        #expect(changeCount == 1)
        #expect(fixture.store.rename(playlist.playlistID, to: "Evening", modelContext: fixture.context))
        #expect(changeCount == 2)
        #expect(fixture.store.setRule(PlaylistRule(status: .played), for: playlist.playlistID, modelContext: fixture.context))
        #expect(changeCount == 3)

        fixture.probe.failsSaves = true
        #expect(!fixture.store.rename(playlist.playlistID, to: "Night", modelContext: fixture.context))
        #expect(!fixture.store.delete(playlist.playlistID, modelContext: fixture.context))
        #expect(changeCount == 3)

        fixture.probe.failsSaves = false
        #expect(fixture.store.delete(playlist.playlistID, modelContext: fixture.context))
        #expect(changeCount == 4)
    }

    @Test("Reset after a data nuke clears loaded playlists")
    func resetAfterDataNukeClearsMemory() throws {
        let fixture = try makeFixture()
        let playlist = try #require(
            fixture.store.create(name: "Commute", modelContext: fixture.context)
        )
        try seedItems([episode("a")], in: playlist.playlistID, fixture: fixture)
        #expect(!fixture.store.rename(playlist.playlistID, to: "", modelContext: fixture.context))
        var changeCount = 0
        fixture.store.onPlaylistsChanged = { changeCount += 1 }

        fixture.store.resetAfterDataNuke()

        #expect(fixture.store.playlists.isEmpty)
        #expect(fixture.store.itemsByPlaylistID.isEmpty)
        #expect(fixture.store.lastErrorMessage == nil)
        #expect(changeCount == 1)
    }

    @Test("Consuming the error clears it")
    func consumeLastErrorMessage() throws {
        let fixture = try makeFixture()
        #expect(!fixture.store.rename("missing", to: "Commute", modelContext: fixture.context))

        let message = fixture.store.consumeLastErrorMessage()

        #expect(message?.contains("no longer exists") == true)
        #expect(fixture.store.lastErrorMessage == nil)
        #expect(fixture.store.consumeLastErrorMessage() == nil)
    }

    private static let january = Date(timeIntervalSince1970: 1_767_355_200)
    private static let february = Date(timeIntervalSince1970: 1_770_033_600)
    @Test("Deleting a playlist writes one playlist tombstone in the same save and none per item")
    func deleteWritesOnePlaylistTombstone() throws {
        let fixture = try makeFixture()
        let playlist = try #require(
            fixture.store.create(name: "Commute", modelContext: fixture.context)
        )
        try seedItems([episode("a"), episode("b")], in: playlist.playlistID, fixture: fixture)
        let saveCount = fixture.probe.saveCount

        #expect(fixture.store.delete(playlist.playlistID, modelContext: fixture.context))

        #expect(fixture.probe.saveCount == saveCount + 1)
        let storedContext = ModelContext(fixture.container)
        let tombstones = try storedTombstones(in: storedContext)
        #expect(tombstones.count == 1)
        #expect(tombstones.first?.playlistID == playlist.playlistID)
        #expect(tombstones.first?.episodeID == nil)
        #expect(tombstones.first?.deletedAt == fixture.probe.latestDate)
        #expect(try storedPlaylists(in: storedContext).isEmpty)
        #expect(try storedItems(in: storedContext).isEmpty)
    }

    @Test("An empty store gets the default All playlist under its fixed ID, and a deleted one stays deleted")
    func emptyLoadCreatesDefaultAllOnceDeleted() throws {
        let fixture = try makeFixture()
        fixture.store.load(modelContext: fixture.context)
        #expect(fixture.store.playlists.map(\.playlistID) == [PlaylistStore.defaultAllPlaylistID])
        #expect(fixture.store.playlists.map(\.name) == ["All Episodes"])

        #expect(fixture.store.delete(PlaylistStore.defaultAllPlaylistID, modelContext: fixture.context))
        fixture.store.load(modelContext: fixture.context)

        #expect(fixture.store.playlists.isEmpty)
        #expect(try storedPlaylists(in: ModelContext(fixture.container)).isEmpty)
    }

    @Test("Deleting a playlist whose rows are already gone still writes its tombstone")
    func deleteOfMemoryOnlyPlaylistWritesTombstone() throws {
        let fixture = try makeFixture()
        let playlist = try #require(
            fixture.store.create(name: "Commute", modelContext: fixture.context)
        )
        let otherContext = ModelContext(fixture.container)
        for record in try storedPlaylists(in: otherContext) {
            otherContext.delete(record)
        }
        try otherContext.save()
        let saveCount = fixture.probe.saveCount

        #expect(fixture.store.delete(playlist.playlistID, modelContext: fixture.context))

        #expect(fixture.probe.saveCount == saveCount + 1)
        #expect(fixture.store.playlists.isEmpty)
        let tombstones = try storedTombstones(in: ModelContext(fixture.container))
        #expect(tombstones.map(\.playlistID) == [playlist.playlistID])
        #expect(tombstones.first?.episodeID == nil)
    }

    @Test("A failed delete rolls the tombstone back with the rows")
    func failedSaveRollsBackTombstones() throws {
        let fixture = try makeFixture()
        let playlist = try #require(
            fixture.store.create(name: "Commute", modelContext: fixture.context)
        )
        try seedItems([episode("a"), episode("b")], in: playlist.playlistID, fixture: fixture)
        fixture.probe.failsSaves = true

        #expect(!fixture.store.delete(playlist.playlistID, modelContext: fixture.context))
        #expect(try fixture.context.fetch(FetchDescriptor<PlaylistTombstoneRecord>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<PlaylistRecord>()).count == 1)
        #expect(try fixture.context.fetch(FetchDescriptor<PlaylistItemRecord>()).count == 2)
        #expect(try storedTombstones(in: ModelContext(fixture.container)).isEmpty)
    }

    @Test("A reload over unchanged rows publishes nothing and does not notify")
    func reloadWithoutChangesIsQuiet() throws {
        let fixture = try makeFixture()
        let playlist = try #require(
            fixture.store.create(name: "Commute", modelContext: fixture.context)
        )
        try seedItems([episode("a"), episode("b")], in: playlist.playlistID, fixture: fixture)
        let playlistsBefore = fixture.store.playlists
        let itemsBefore = fixture.store.itemsByPlaylistID
        var changeCount = 0
        fixture.store.onPlaylistsChanged = { changeCount += 1 }

        let change = fixture.store.reload(modelContext: fixture.context)

        #expect(change == PlaylistReloadChange())
        #expect(changeCount == 0)
        #expect(fixture.store.playlists == playlistsBefore)
        #expect(fixture.store.itemsByPlaylistID == itemsBefore)
    }

    @Test("A reload lists one row per twin pair (the smallest playlist identity, the newest-added item), and reports repair")
    func reloadListsTwinWinners() throws {
        let fixture = try makeFixture()
        fixture.store.load(modelContext: fixture.context)
        let older = Date(timeIntervalSince1970: 1_775_000_000)
        fixture.context.insert(
            PlaylistRecord(
                playlistID: "twin",
                name: "Winner Identity",
                createdAt: older,
                updatedAt: older,
                dedupeUUID: Self.firstDedupeUUID
            )
        )
        fixture.context.insert(
            PlaylistRecord(
                playlistID: "twin",
                name: "Newer Copy",
                createdAt: older,
                updatedAt: older.addingTimeInterval(60),
                dedupeUUID: Self.lastDedupeUUID
            )
        )
        // The item twins invert the playlist pick: the smallest identity was
        // added first, so the larger identity's newer add is the listed row.
        fixture.context.insert(
            itemRow(itemID: "loser-item", playlistID: "twin", episodeID: "a", dedupeUUID: Self.firstDedupeUUID)
        )
        fixture.context.insert(
            itemRow(
                itemID: "winner-item",
                playlistID: "twin",
                episodeID: "a",
                addedAt: Self.march.addingTimeInterval(60),
                dedupeUUID: Self.lastDedupeUUID
            )
        )
        try fixture.context.save()
        var changeCount = 0
        fixture.store.onPlaylistsChanged = { changeCount += 1 }

        let change = fixture.store.reload(modelContext: fixture.context)

        #expect(change.didChange)
        #expect(change.needsRepair)
        #expect(change.removedPlaylistIDs.isEmpty)
        #expect(change.renamedPlaylistIDs.isEmpty)
        #expect(changeCount == 1)
        // "All Episodes" is the smart playlist the store creates when it loads empty.
        #expect(fixture.store.playlists.map(\.name) == ["All Episodes", "Winner Identity"])
        #expect(fixture.store.itemsByPlaylistID["twin"]?.map(\.itemID) == ["winner-item"])
        #expect(fixture.store.playlists.first { $0.playlistID == "twin" }?.itemCount == 1)
        #expect(try storedItems(in: ModelContext(fixture.container)).count == 2)
    }

    @Test("A reload hides a tombstoned playlist and a shadowed item, reports repair, and deletes no row")
    func reloadHidesShadowedRows() throws {
        let fixture = try makeFixture()
        let kept = try #require(fixture.store.create(name: "Kept", modelContext: fixture.context))
        let deleted = try #require(fixture.store.create(name: "Deleted", modelContext: fixture.context))
        try seedItems([episode("a"), episode("b")], in: kept.playlistID, fixture: fixture)
        let addedAt = Self.march
        fixture.context.insert(PlaylistTombstoneRecord(playlistID: deleted.playlistID, deletedAt: .distantPast))
        fixture.context.insert(PlaylistTombstoneRecord(playlistID: kept.playlistID, episodeID: "a", deletedAt: addedAt))
        try fixture.context.save()

        let change = fixture.store.reload(modelContext: fixture.context)

        #expect(change.didChange)
        #expect(change.needsRepair)
        #expect(change.removedPlaylistIDs == [deleted.playlistID])
        #expect(fixture.store.playlists.map(\.playlistID) == [kept.playlistID])
        #expect(fixture.store.itemsByPlaylistID[kept.playlistID]?.map(\.episodeID) == ["b"])
        #expect(fixture.store.itemsByPlaylistID[deleted.playlistID] == nil)
        let storedContext = ModelContext(fixture.container)
        #expect(try storedPlaylists(in: storedContext).count == 2)
        #expect(try storedItems(in: storedContext).count == 2)
    }

    @Test("A reload reports the playlists that left and the ones renamed behind the store")
    func reloadReportsRemovedAndRenamed() throws {
        let fixture = try makeFixture()
        let unchanged = try #require(fixture.store.create(name: "Unchanged", modelContext: fixture.context))
        let removed = try #require(fixture.store.create(name: "Removed", modelContext: fixture.context))
        let renamed = try #require(fixture.store.create(name: "Renamed", modelContext: fixture.context))
        for record in try storedPlaylists(in: fixture.context) {
            if record.playlistID == removed.playlistID {
                fixture.context.delete(record)
            } else if record.playlistID == renamed.playlistID {
                record.name = "Evening"
            }
        }
        try fixture.context.save()
        var changeCount = 0
        fixture.store.onPlaylistsChanged = { changeCount += 1 }

        let change = fixture.store.reload(modelContext: fixture.context)

        #expect(change.didChange)
        #expect(!change.needsRepair)
        #expect(change.removedPlaylistIDs == [removed.playlistID])
        #expect(change.renamedPlaylistIDs == [renamed.playlistID])
        #expect(changeCount == 1)
        #expect(Set(fixture.store.playlists.map(\.playlistID)) == [unchanged.playlistID, renamed.playlistID])
        #expect(fixture.store.playlists.first { $0.playlistID == renamed.playlistID }?.name == "Evening")
    }

    @Test("A reload drops the smart evaluations of the playlists that left")
    func reloadDropsRemovedEvaluations() throws {
        let fixture = try makeFixture()
        let removed = try #require(fixture.store.create(name: "Removed", modelContext: fixture.context))
        let kept = try #require(fixture.store.create(name: "Kept", modelContext: fixture.context))
        let cache = fixture.store.smartEvaluations
        let key = memoKey()
        _ = cache.evaluation(for: removed.playlistID, key: key) { [episode("a")] }
        _ = cache.evaluation(for: kept.playlistID, key: key) { [episode("b")] }
        #expect(cache.computeCount == 2)
        let otherContext = ModelContext(fixture.container)
        for record in try storedPlaylists(in: otherContext) where record.playlistID == removed.playlistID {
            otherContext.delete(record)
        }
        try otherContext.save()

        let change = fixture.store.reload(modelContext: fixture.context)

        #expect(change.removedPlaylistIDs == [removed.playlistID])
        let recomputed = cache.evaluation(for: removed.playlistID, key: key) { [] }
        #expect(recomputed == .empty)
        #expect(cache.computeCount == 3)
        let untouched = cache.evaluation(for: kept.playlistID, key: key) { [] }
        #expect(untouched.episodes.map(\.episodeID) == ["b"])
        #expect(cache.computeCount == 3)
    }

    @Test("After a committed identity re-key a reload reports no change")
    func reloadAfterCommittedRekeyIsQuiet() throws {
        let successorPodcastID = "https://example.com/new.xml"
        let fixture = try makeFixture()
        let playlist = try #require(
            fixture.store.create(name: "Commute", modelContext: fixture.context)
        )
        try seedItems([episode("a"), episode("old")], in: playlist.playlistID, fixture: fixture)
        var changeCount = 0
        fixture.store.onPlaylistsChanged = { changeCount += 1 }

        // The applier rewrites the rows in the same context and the same
        // save as the memory staging, then the save commits.
        try fixture.store.migrateEpisodeSidecars(
            from: "old",
            to: "new",
            canonicalPodcastID: successorPodcastID,
            modelContext: fixture.context
        )
        let departed = try #require(try storedItems(in: fixture.context).first { $0.episodeID == "old" })
        departed.episodeID = "new"
        departed.podcastID = successorPodcastID
        fixture.context.insert(
            PlaylistTombstoneRecord(playlistID: playlist.playlistID, episodeID: "old", deletedAt: fixture.probe.latestDate)
        )
        try fixture.context.save()
        fixture.store.finishEpisodeSidecarMigration(committed: true)
        #expect(changeCount == 1)

        let change = fixture.store.reload(modelContext: fixture.context)

        #expect(change == PlaylistReloadChange())
        #expect(changeCount == 1)
        #expect(fixture.store.itemsByPlaylistID[playlist.playlistID]?.map(\.episodeID) == ["a", "new"])
    }

    @Test("A reload never rolls back the context's pending changes")
    func reloadKeepsPendingChanges() throws {
        let fixture = try makeFixture()
        _ = try #require(fixture.store.create(name: "Commute", modelContext: fixture.context))
        fixture.context.insert(SubscriptionRecord(feedURL: "https://example.com/pending.xml", title: "Pending Show"))
        #expect(fixture.context.hasChanges)

        fixture.store.reload(modelContext: fixture.context)

        #expect(fixture.context.hasChanges)
        #expect(fixture.context.insertedModelsArray.contains { $0 is SubscriptionRecord })
    }

    @Test("Item rows whose playlist is not listed stay out of memory and stay in the store")
    func parentlessItemRowsStayStored() throws {
        let fixture = try makeFixture()
        fixture.context.insert(itemRow(itemID: "ghost-item", playlistID: "ghost", episodeID: "a"))
        try fixture.context.save()
        fixture.store.load(modelContext: fixture.context)
        #expect(fixture.store.itemsByPlaylistID["ghost"] == nil)

        let playlist = try #require(
            fixture.store.create(name: "Commute", modelContext: fixture.context)
        )
        try seedItems([episode("a")], in: playlist.playlistID, fixture: fixture)
        let change = fixture.store.reload(modelContext: fixture.context)

        #expect(!change.didChange)
        #expect(fixture.store.itemsByPlaylistID["ghost"] == nil)
        let ghostRows = try storedItems(in: ModelContext(fixture.container)).filter { $0.playlistID == "ghost" }
        #expect(ghostRows.map(\.itemID) == ["ghost-item"])
    }

    private static let march = Date(timeIntervalSince1970: 1_772_452_800)
    /// Below and above every uppercase `UUID().uuidString`, so a hand-made
    /// twin loses or wins against a row the store minted.
    private static let firstDedupeUUID = "00000000-0000-0000-0000-000000000000"
    private static let lastDedupeUUID = "zzzzzzzz-0000-0000-0000-000000000000"

    private func itemRow(
        itemID: String,
        playlistID: String,
        episodeID: String,
        addedAt: Date = Self.march,
        dedupeUUID: String = UUID().uuidString
    ) -> PlaylistItemRecord {
        PlaylistItemRecord(
            itemID: itemID,
            playlistID: playlistID,
            episodeID: episodeID,
            podcastID: "https://example.com/feed.xml",
            sortKey: "1",
            addedAt: addedAt,
            updatedAt: Self.march,
            episodeTitle: "Episode \(episodeID)",
            podcastTitle: "Example Show",
            duration: 60,
            dedupeUUID: dedupeUUID
        )
    }

    /// Item rows from the retired hand-picked playlists, inserted directly
    /// and reloaded, as they arrive by sync.
    private func seedItems(
        _ episodes: [EpisodeListItemSnapshot],
        in playlistID: String,
        fixture: (
            store: PlaylistStore,
            probe: PlaylistStoreProbe,
            context: ModelContext,
            container: ModelContainer
        )
    ) throws {
        let sortKeys = PlaylistSortKey.renumbered(count: episodes.count)
        for (offset, episode) in episodes.enumerated() {
            fixture.context.insert(
                PlaylistItemRecord(
                    itemID: UUID().uuidString,
                    playlistID: playlistID,
                    episodeID: episode.episodeID,
                    podcastID: episode.podcastID,
                    sortKey: sortKeys[offset],
                    addedAt: Self.march,
                    updatedAt: Self.march,
                    episodeTitle: episode.title,
                    podcastTitle: episode.podcastTitle,
                    duration: episode.duration
                )
            )
        }
        try fixture.context.save()
        fixture.store.reload(modelContext: fixture.context)
    }

    private func storedTombstones(in context: ModelContext) throws -> [PlaylistTombstoneRecord] {
        try context.fetch(FetchDescriptor<PlaylistTombstoneRecord>())
    }

    private func makeFixture() throws -> (
        store: PlaylistStore,
        probe: PlaylistStoreProbe,
        context: ModelContext,
        container: ModelContainer
    ) {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let probe = PlaylistStoreProbe()
        let store = PlaylistStore(
            saveSyncedStore: SyncedStoreSelfSaveLedger(performSave: probe.save).save,
            now: probe.nextDate
        )
        return (store, probe, ModelContext(container), container)
    }

    private func expectBumpedUpdatedAt(
        _ playlistID: String,
        since previous: Date,
        fixture: (
            store: PlaylistStore,
            probe: PlaylistStoreProbe,
            context: ModelContext,
            container: ModelContainer
        )
    ) throws -> Date {
        let summary = try #require(fixture.store.playlists.first(where: { $0.playlistID == playlistID }))
        let storedContext = ModelContext(fixture.container)
        let records = try storedPlaylists(in: storedContext)
        let record = try #require(records.first(where: { $0.playlistID == playlistID }))
        #expect(summary.updatedAt > previous)
        #expect(summary.updatedAt == fixture.probe.latestDate)
        #expect(record.updatedAt == summary.updatedAt)
        return summary.updatedAt
    }

    private func storedPlaylists(in context: ModelContext) throws -> [PlaylistRecord] {
        try context.fetch(FetchDescriptor<PlaylistRecord>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    private func storedItems(in context: ModelContext) throws -> [PlaylistItemRecord] {
        try context.fetch(
            FetchDescriptor<PlaylistItemRecord>(
                sortBy: [
                    SortDescriptor(\.sortKey, comparator: .lexical),
                    SortDescriptor(\.addedAt),
                    SortDescriptor(\.itemID, comparator: .lexical)
                ]
            )
        )
    }

    private func storedKeysByItemID(in container: ModelContainer) throws -> [String: String] {
        let context = ModelContext(container)
        return try Dictionary(
            uniqueKeysWithValues: storedItems(in: context).map { ($0.itemID, $0.sortKey) }
        )
    }

    private func memoKey() -> SmartPlaylistEvaluationKey {
        SmartPlaylistEvaluationKey(
            ruleJSON: PlaylistRule.default.encodedJSON(),
            episodeRevision: 1,
            progressRevision: 1,
            downloadsRevision: nil,
            referenceDate: nil
        )
    }

    private func episode(
        _ episodeID: String,
        podcastID: String = "https://example.com/feed.xml",
        publishedAt: Date? = nil,
        duration: TimeInterval? = 60
    ) -> EpisodeListItemSnapshot {
        .fixture(
            episodeID: episodeID,
            podcastID: podcastID,
            publishedAt: publishedAt,
            duration: duration,
            audioURL: "https://example.com/\(episodeID).mp3",
            guid: episodeID
        )
    }

    private func isStrictlyAscending(_ keys: [String]) -> Bool {
        zip(keys, keys.dropFirst()).allSatisfy { $0 < $1 }
    }
}

/// Stands in for the store's save and clock seams: saves can be made to fail
/// after the store has mutated the context, and every date the store asks for
/// is a minute after the last so `updatedAt` bumps are exact.
private final class PlaylistStoreProbe {
    var failsSaves = false
    private(set) var saveCount = 0
    private(set) var latestDate = Date(timeIntervalSince1970: 1_775_000_000)

    func save(_ context: ModelContext) throws {
        saveCount += 1
        if failsSaves {
            throw PlaylistSaveFailure()
        }
        try context.save()
    }

    func nextDate() -> Date {
        latestDate = latestDate.addingTimeInterval(60)
        return latestDate
    }
}

private struct PlaylistSaveFailure: LocalizedError {
    var errorDescription: String? {
        "Simulated playlist save failure"
    }
}
