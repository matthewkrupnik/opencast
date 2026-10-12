import Foundation
import OpenCastCore
import OpenCastTranscription
import SwiftData
import Testing
@testable import OpenCast

@MainActor
@Suite("Episode transcript analysis store")
struct EpisodeTranscriptAnalysisStoreTests {
    @Test("Creates analysis record and document from client response")
    func createsRecordAndDocumentFromClientResponse() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let client = FakeEpisodeTranscriptAnalysisClient()
        let store = EpisodeTranscriptAnalysisStore(
            client: client,
            fileStore: EpisodeTranscriptAnalysisFileStore(baseDirectory: try makeTemporaryDirectory())
        )
        let transcript = makeTranscriptDocument(episodeID: "chapters-create")

        store.startAnalysis(
            transcript: transcript,
            episodeTitle: "Episode Title",
            podcastTitle: "Podcast Title",
            modelContext: context
        )

        #expect(await waitUntil {
            store.record(for: transcript.episodeID)?.state == .completed
        })
        let record = try #require(store.record(for: transcript.episodeID))
        let document = try #require(store.document(for: transcript.episodeID))
        let request = try #require(client.lastRequest)
        let encodedRequest = String(
            decoding: try EpisodeTranscriptAnalysisJSONCoding.encoder().encode(request),
            as: UTF8.self
        )
        #expect(record.chapterCount == 2)
        #expect(record.policy == "transcript_analysis_v2")
        #expect(document.chapters.map(\.title) == ["Welcome", "The Sponsor Read"])
        #expect(document.chapters[1].startSegmentID == 1)
        #expect(document.summary?.oneLineDescription == "A short test episode")
        #expect(document.summary?.claims.first?.evidenceSegmentID == 0)
        #expect(document.transcriptSegmentCount == transcript.segments.count)
        // H2: real titles are on the wire — a nil title would change prompt
        // bytes and void the request validation.
        #expect(request.episodeTitle == "Episode Title")
        #expect(request.podcastTitle == "Podcast Title")
        #expect(encodedRequest.contains(#""episode_title":"Episode Title""#))
        // Sharing ships dark — every request declares it off.
        #expect(request.allowShared == false)
        #expect(encodedRequest.contains(#""allow_shared":false"#))
        #expect(encodedRequest.contains(#""async_supported":true"#))
        #expect(!encodedRequest.contains(transcript.sourceAudioURL))
        #expect(!encodedRequest.contains(transcript.sourceFileSHA256))
    }

    @Test("Cap rejections thread the capExceeded kind and surface as deferred")
    func capRejectionsThreadCapExceededAndDefer() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let client = ThrowingEpisodeTranscriptAnalysisClient(
            error: EpisodeTranscriptAnalysisHTTPError(
                statusCode: 429,
                code: "daily_request_cap_exceeded",
                detail: nil
            )
        )
        let store = EpisodeTranscriptAnalysisStore(
            client: client,
            fileStore: EpisodeTranscriptAnalysisFileStore(baseDirectory: try makeTemporaryDirectory())
        )
        let transcript = makeTranscriptDocument(episodeID: "chapters-cap")

        store.startAnalysis(
            transcript: transcript,
            episodeTitle: "Episode Title",
            podcastTitle: "Podcast Title",
            modelContext: context
        )

        #expect(await waitUntil {
            store.record(for: transcript.episodeID)?.state == .failed
        })
        let record = try #require(store.record(for: transcript.episodeID))
        #expect(record.failureKind == .capExceeded)
        #expect(store.capDeferredEpisodeIDs == [transcript.episodeID])
    }

    @Test("A defensive async_required 400 stays a generic quiet failure")
    func asyncRequiredStaysGenericQuietFailure() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let client = ThrowingEpisodeTranscriptAnalysisClient(
            error: EpisodeTranscriptAnalysisHTTPError(
                statusCode: 400,
                code: "async_required",
                detail: nil
            )
        )
        let store = EpisodeTranscriptAnalysisStore(
            client: client,
            fileStore: EpisodeTranscriptAnalysisFileStore(baseDirectory: try makeTemporaryDirectory())
        )
        let transcript = makeTranscriptDocument(episodeID: "chapters-async-required")

        store.startAnalysis(
            transcript: transcript,
            episodeTitle: "Episode Title",
            podcastTitle: "Podcast Title",
            modelContext: context
        )

        #expect(await waitUntil {
            store.record(for: transcript.episodeID)?.state == .failed
        })
        let record = try #require(store.record(for: transcript.episodeID))
        #expect(record.failureKind == .generic)
        #expect(store.insufficientSecondsDeferredEpisodeIDs.isEmpty)
        #expect(store.capDeferredEpisodeIDs.isEmpty)
    }

    @Test("Generic failures never join the cap-deferred retry set")
    func genericFailuresAreNotCapDeferred() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let client = ThrowingEpisodeTranscriptAnalysisClient(
            error: EpisodeTranscriptAnalysisHTTPError(
                statusCode: 502,
                code: "model_output_truncated",
                detail: nil
            )
        )
        let store = EpisodeTranscriptAnalysisStore(
            client: client,
            fileStore: EpisodeTranscriptAnalysisFileStore(baseDirectory: try makeTemporaryDirectory())
        )
        let transcript = makeTranscriptDocument(episodeID: "chapters-502")

        store.startAnalysis(
            transcript: transcript,
            episodeTitle: "Episode Title",
            podcastTitle: "Podcast Title",
            modelContext: context
        )

        #expect(await waitUntil {
            store.record(for: transcript.episodeID)?.state == .failed
        })
        let record = try #require(store.record(for: transcript.episodeID))
        #expect(record.failureKind == .generic)
        #expect(store.capDeferredEpisodeIDs.isEmpty)
        #expect(store.document(for: transcript.episodeID) == nil)
    }

    @Test("A response from an unexpected policy fails cleanly")
    func unexpectedPolicyResponseFailsCleanly() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let client = FakeEpisodeTranscriptAnalysisClient()
        client.policy = "transcript_analysis_v999"
        let store = EpisodeTranscriptAnalysisStore(
            client: client,
            fileStore: EpisodeTranscriptAnalysisFileStore(baseDirectory: try makeTemporaryDirectory())
        )
        let transcript = makeTranscriptDocument(episodeID: "chapters-policy")

        store.startAnalysis(
            transcript: transcript,
            episodeTitle: "Episode Title",
            podcastTitle: "Podcast Title",
            modelContext: context
        )

        #expect(await waitUntil {
            store.record(for: transcript.episodeID)?.state == .failed
        })
        let record = try #require(store.record(for: transcript.episodeID))
        #expect(record.failureKind == .generic)
        #expect(store.document(for: transcript.episodeID) == nil)
    }

    @Test("A completed analysis with no chapters and no summary is never current")
    func contentlessCompletedAnalysisIsNeverCurrent() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        // The throwing client's success path returns a completed response
        // with zero chapters and no summary.
        let client = ThrowingEpisodeTranscriptAnalysisClient(error: nil)
        let store = EpisodeTranscriptAnalysisStore(
            client: client,
            fileStore: EpisodeTranscriptAnalysisFileStore(baseDirectory: try makeTemporaryDirectory())
        )
        let transcript = makeTranscriptDocument(episodeID: "chapters-contentless")

        store.startAnalysis(
            transcript: transcript,
            episodeTitle: "Episode Title",
            podcastTitle: "Podcast Title",
            modelContext: context
        )

        #expect(await waitUntil {
            !store.hasActiveJob && store.record(for: transcript.episodeID)?.state == .completed
        })
        let document = try #require(store.document(for: transcript.episodeID))
        #expect(!document.hasPresentableContent)

        // Rendering neither card while also reporting "current" would hide
        // Generate permanently; the empty result must not count as current
        // for the detail surface or for the auto-run/explicit skip check.
        let state = await store.episodeDetailState(
            for: transcript,
            transcriptState: .completed,
            analysisDocument: document
        )
        #expect(!state.hasCurrentCompletedAnalysis)
        guard case .completed(_, let isStale) = state.jobState else {
            Issue.record("Expected a completed job state, got \(state.jobState)")
            return
        }
        #expect(!isStale)
        #expect(await !store.hasCurrentCompletedAnalysis(for: transcript))
    }

    @Test("Completed analysis is stale once the transcript changes")
    func completedAnalysisIsStaleOnceTranscriptChanges() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let client = FakeEpisodeTranscriptAnalysisClient()
        let store = EpisodeTranscriptAnalysisStore(
            client: client,
            fileStore: EpisodeTranscriptAnalysisFileStore(baseDirectory: try makeTemporaryDirectory())
        )
        let transcript = makeTranscriptDocument(episodeID: "chapters-stale")

        store.startAnalysis(
            transcript: transcript,
            episodeTitle: "Episode Title",
            podcastTitle: "Podcast Title",
            modelContext: context
        )
        #expect(await waitUntil {
            !store.hasActiveJob && store.record(for: transcript.episodeID)?.state == .completed
        })

        guard case .completed(_, let freshIsStale) = store.jobState(for: transcript) else {
            Issue.record("Expected a completed job state for the unchanged transcript")
            return
        }
        #expect(!freshIsStale)

        var changedTranscript = transcript
        changedTranscript.segments[1].text += " (remastered)"
        changedTranscript.text = changedTranscript.segments.map(\.text).joined(separator: " ")
        guard case .completed(_, let changedIsStale) = store.jobState(for: changedTranscript) else {
            Issue.record("Expected a completed job state for the changed transcript")
            return
        }
        #expect(changedIsStale)
    }

    @Test("An active job never marks other episodes as running")
    func activeJobNeverMarksOtherEpisodesRunning() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let gate = SuspensionGate()
        let client = GatedEpisodeTranscriptAnalysisClient(gate: gate)
        let store = EpisodeTranscriptAnalysisStore(
            client: client,
            fileStore: EpisodeTranscriptAnalysisFileStore(baseDirectory: try makeTemporaryDirectory())
        )
        let runningTranscript = makeTranscriptDocument(episodeID: "chapters-running-a")
        let otherTranscript = makeTranscriptDocument(episodeID: "chapters-idle-b")

        store.startAnalysis(
            transcript: runningTranscript,
            episodeTitle: "Episode Title",
            podcastTitle: "Podcast Title",
            modelContext: context
        )
        #expect(store.isRunning(for: runningTranscript.episodeID))

        // Episode B was never queued: while A's job is in flight it must
        // offer Generate, not report A's run as its own. (The detail view
        // invalidates on its own episode's isRunning flag, so a borrowed
        // running state would outlive A's job.)
        guard case .running = store.jobState(for: runningTranscript) else {
            Issue.record("Expected the active episode to report running")
            return
        }
        #expect(!store.isRunning(for: otherTranscript.episodeID))
        guard case .ready = store.jobState(for: otherTranscript) else {
            Issue.record("Expected the uninvolved episode to stay ready, got \(store.jobState(for: otherTranscript))")
            return
        }

        await gate.open()
        #expect(await waitUntil { !store.hasActiveJob })
    }

    @Test("Transcript analysis record is local-only but included in full schema")
    func transcriptAnalysisRecordIsLocalOnly() {
        let localEntityNames = OpenCastModelContainerFactory.localSchema.entities.map(\.name)
        let syncedEntityNames = OpenCastModelContainerFactory.syncedSchema.entities.map(\.name)
        let fullEntityNames = OpenCastModelContainerFactory.fullSchema.entities.map(\.name)
        #expect(localEntityNames.contains("EpisodeTranscriptAnalysisRecord"))
        #expect(!syncedEntityNames.contains("EpisodeTranscriptAnalysisRecord"))
        #expect(fullEntityNames.contains("EpisodeTranscriptAnalysisRecord"))
    }

    @Test("Duplicate repair OR-merges the opt-in onto the deterministic winner")
    func duplicateRepairORMergesOptIn() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let store = LibraryStore(localCache: SQLiteLocalLibraryCacheStore.inMemory())
        let feedURL = "https://example.com/chapters-merge.xml"

        // The winner (smallest dedupeUUID) has the flag OFF; a losing twin
        // carries the explicit opt-in. The merge must keep the winner row and
        // the consent.
        context.insert(
            SubscriptionRecord(
                feedURL: feedURL,
                title: "Winner Copy",
                isTranscriptAnalysisEnabled: false,
                dedupeUUID: "aaaaaaaa-0000-0000-0000-000000000000"
            )
        )
        context.insert(
            SubscriptionRecord(
                feedURL: feedURL,
                title: "Loser Copy",
                isTranscriptAnalysisEnabled: true,
                dedupeUUID: "bbbbbbbb-0000-0000-0000-000000000000"
            )
        )
        try context.save()

        _ = try await store.repairSyncDuplicates(modelContext: context)

        let subscriptions = try context.fetch(FetchDescriptor<SubscriptionRecord>())
        #expect(subscriptions.count == 1)
        let survivor = try #require(subscriptions.first)
        #expect(survivor.dedupeUUID == "aaaaaaaa-0000-0000-0000-000000000000")
        #expect(survivor.isTranscriptAnalysisEnabled == true)
    }

    @Test("Legacy duplicate replacement carries the opt-in onto the fresh record")
    func legacyDuplicateReplacementCarriesOptIn() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let store = LibraryStore(localCache: SQLiteLocalLibraryCacheStore.inMemory())
        let feedURL = "https://example.com/chapters-legacy-merge.xml"

        context.insert(
            SubscriptionRecord(feedURL: feedURL, title: "Legacy Off", isTranscriptAnalysisEnabled: false, dedupeUUID: "")
        )
        context.insert(
            SubscriptionRecord(feedURL: feedURL, title: "Legacy On", isTranscriptAnalysisEnabled: true, dedupeUUID: "")
        )
        try context.save()

        _ = try await store.repairSyncDuplicates(modelContext: context)

        let subscriptions = try context.fetch(FetchDescriptor<SubscriptionRecord>())
        #expect(subscriptions.count == 1)
        let survivor = try #require(subscriptions.first)
        #expect(!survivor.dedupeUUID.isEmpty)
        #expect(survivor.isTranscriptAnalysisEnabled == true)
    }

    @Test("Generate disclosure copy composes from the feature flags")
    func generateDisclosureCopyComposesFromFlags() {
        // All flags live pins the full first-tap disclosure byte-for-byte.
        let pinnedBody = """
        This episode’s transcript is sent from this device to Google Gemini to generate chapters and a summary. Your audio is never sent.
        Results are saved on this device.
        Chapters may be shared with other listeners of the same episode.
        """
        #expect(
            TranscriptAnalysisGenerateDisclosureCopy.confirmationBody(
                isSharingEnabled: true
            ) == pinnedBody
        )

        // Sharing dark composes down to the base disclosure alone.
        let darkBody = TranscriptAnalysisGenerateDisclosureCopy.confirmationBody(
            isSharingEnabled: false
        )
        #expect(!darkBody.contains("shared"))
        #expect(darkBody == """
        This episode’s transcript is sent from this device to Google Gemini to generate chapters and a summary. Your audio is never sent.
        Results are saved on this device.
        """)

        // Shipping flags: sharing stays dark, so the sharing sentence must
        // not appear.
        let shippingBody = TranscriptAnalysisGenerateDisclosureCopy.confirmationBody()
        #expect(!shippingBody.contains("shared"))
        #expect(shippingBody == """
        This episode’s transcript is sent from this device to Google Gemini to generate chapters and a summary. Your audio is never sent.
        Results are saved on this device.
        """)
        #expect(TranscriptAnalysisGenerateDisclosureCopy.title == "Generate Chapters & Summary?")
        #expect(TranscriptAnalysisGenerateDisclosureCopy.confirmButtonTitle == "Generate")
    }

    @Test("Cap retry probe drains past ineligible deferrals and stale cap records never starve the queue")
    func capRetryProbeDrainsPastIneligibleDeferralsAndStaleCapRecordsDoNotStarve() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let localCache = SQLiteLocalLibraryCacheStore.inMemory()
        let temporaryDirectory = try makeTemporaryDirectory()
        let transcriptFileStore = EpisodeTranscriptFileStore(baseDirectory: temporaryDirectory)
        let client = FakeEpisodeTranscriptAnalysisClient()
        let transcriptAnalyses = EpisodeTranscriptAnalysisStore(
            client: client,
            fileStore: EpisodeTranscriptAnalysisFileStore(baseDirectory: temporaryDirectory)
        )

        // One deferral belongs to an episode that was never transcribed —
        // the eligibility gate skips it. The transcribed show has an episode
        // with creator chapters (the gate skips it too, without touching its
        // record) ahead of a plain episode the worker now admits.
        let untranscribedSnapshot = try RSSFeedParser().parse(
            data: Data(
                """
                <?xml version="1.0" encoding="utf-8"?>
                <rss version="2.0">
                  <channel>
                    <title>Untranscribed Show</title>
                    <item>
                      <title>Untranscribed Episode</title>
                      <guid>cap-optout-1</guid>
                      <enclosure url="https://example.com/audio/cap-optout-1.mp3" type="audio/mpeg" />
                    </item>
                  </channel>
                </rss>
                """.utf8
            ),
            feedURL: URL(string: "https://example.com/cap-optout.xml")!
        )
        let transcribedSnapshot = try RSSFeedParser().parse(
            data: Data(
                """
                <?xml version="1.0" encoding="utf-8"?>
                <rss version="2.0">
                  <channel>
                    <title>Transcribed Show</title>
                    <item>
                      <title>Creator Chaptered</title>
                      <guid>cap-optin-chaptered</guid>
                      <podcast:chapters url="https://example.com/chapters/cap-optin.json" type="application/json+chapters" />
                      <enclosure url="https://example.com/audio/cap-optin-chaptered.mp3" type="audio/mpeg" />
                    </item>
                    <item>
                      <title>Plain</title>
                      <guid>cap-optin-plain</guid>
                      <enclosure url="https://example.com/audio/cap-optin-plain.mp3" type="audio/mpeg" />
                    </item>
                  </channel>
                </rss>
                """.utf8
            ),
            feedURL: URL(string: "https://example.com/cap-optin.xml")!
        )
        try await localCache.upsertCache(from: untranscribedSnapshot, refreshedAt: .now)
        try await localCache.upsertCache(from: transcribedSnapshot, refreshedAt: .now)

        let untranscribedFeedURL = untranscribedSnapshot.podcast.id.rawValue
        let transcribedFeedURL = transcribedSnapshot.podcast.id.rawValue
        let untranscribedEpisodeID = untranscribedSnapshot.episodes[0].id.rawValue
        let chapteredEpisodeID = transcribedSnapshot.episodes[0].id.rawValue
        let plainEpisodeID = transcribedSnapshot.episodes[1].id.rawValue
        context.insert(SubscriptionRecord(feedURL: untranscribedFeedURL, title: "Untranscribed Show"))
        context.insert(SubscriptionRecord(feedURL: transcribedFeedURL, title: "Transcribed Show"))
        for episodeID in [chapteredEpisodeID, plainEpisodeID] {
            try seedCompletedTranscript(
                episodeID: episodeID,
                podcastID: transcribedFeedURL,
                fileStore: transcriptFileStore,
                context: context
            )
        }
        // All three carry cap denials from an earlier session; updatedAt
        // ordering drains both gate-skipped episodes before the runnable one.
        let base = Date(timeIntervalSince1970: 1_780_100_000)
        insertCapDeferredRecord(
            episodeID: untranscribedEpisodeID,
            podcastID: untranscribedFeedURL,
            updatedAt: base.addingTimeInterval(20),
            context: context
        )
        insertCapDeferredRecord(
            episodeID: chapteredEpisodeID,
            podcastID: transcribedFeedURL,
            updatedAt: base.addingTimeInterval(10),
            context: context
        )
        insertCapDeferredRecord(
            episodeID: plainEpisodeID,
            podcastID: transcribedFeedURL,
            updatedAt: base,
            context: context
        )
        try context.save()

        let appModel = OpenCastAppModel(
            library: LibraryStore(localCache: localCache),
            transcriptions: EpisodeTranscriptionStore(fileStore: transcriptFileStore),
            transcriptAnalyses: transcriptAnalyses,
            allowsAutomaticFeedRefresh: false
        )
        await appModel.library.load(modelContext: context)
        appModel.transcriptions.load(modelContext: context)
        // The deferrals model manually started runs, so consent is on file.
        transcriptAnalyses.acknowledgeGenerateDisclosure(modelContext: context)
        appModel.transcriptAnalyses.load(modelContext: context)

        appModel.retryDeferredTranscriptAnalyses(modelContext: context, trigger: .sceneActivated)

        #expect(await waitUntil {
            transcriptAnalyses.record(for: plainEpisodeID)?.state == .completed
                && !transcriptAnalyses.hasActiveJob
        })
        // Only the runnable episode reached the worker: the untranscribed
        // and creator-chaptered deferrals skipped on the eligibility gate,
        // and the stale capExceeded left on both skipped records did not
        // halt the drain behind them.
        #expect(client.requests.map(\.episodeID) == [plainEpisodeID])
        #expect(transcriptAnalyses.record(for: untranscribedEpisodeID)?.failureKind == .capExceeded)
        #expect(transcriptAnalyses.record(for: chapteredEpisodeID)?.failureKind == .capExceeded)
    }

    @Test("Deferrals inherited before the disclosure acknowledgement demote and never re-upload")
    func preConsentDeferralsDemoteInsteadOfRetrying() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let localCache = SQLiteLocalLibraryCacheStore.inMemory()
        let temporaryDirectory = try makeTemporaryDirectory()
        let transcriptFileStore = EpisodeTranscriptFileStore(baseDirectory: temporaryDirectory)
        let client = FakeEpisodeTranscriptAnalysisClient()
        let transcriptAnalyses = EpisodeTranscriptAnalysisStore(
            client: client,
            fileStore: EpisodeTranscriptAnalysisFileStore(baseDirectory: temporaryDirectory)
        )

        // A previous-version install upgrading to manual generation: the
        // retired auto-run left typed deferrals behind for fully eligible
        // episodes (its per-show opt-in may have been withdrawn before the
        // upgrade), and the generate disclosure has never been acknowledged.
        let snapshot = try RSSFeedParser().parse(
            data: Data(
                """
                <?xml version="1.0" encoding="utf-8"?>
                <rss version="2.0">
                  <channel>
                    <title>Legacy Consent Show</title>
                    <item>
                      <title>Cap Deferred</title>
                      <guid>legacy-consent-cap</guid>
                      <enclosure url="https://example.com/audio/legacy-consent-cap.mp3" type="audio/mpeg" />
                    </item>
                    <item>
                      <title>Needs Minutes</title>
                      <guid>legacy-consent-needs</guid>
                      <enclosure url="https://example.com/audio/legacy-consent-needs.mp3" type="audio/mpeg" />
                    </item>
                  </channel>
                </rss>
                """.utf8
            ),
            feedURL: URL(string: "https://example.com/legacy-consent.xml")!
        )
        try await localCache.upsertCache(from: snapshot, refreshedAt: .now)
        let feedURL = snapshot.podcast.id.rawValue
        let capEpisodeID = snapshot.episodes[0].id.rawValue
        let needsMinutesEpisodeID = snapshot.episodes[1].id.rawValue
        context.insert(SubscriptionRecord(feedURL: feedURL, title: "Legacy Consent Show"))
        for episodeID in [capEpisodeID, needsMinutesEpisodeID] {
            try seedCompletedTranscript(
                episodeID: episodeID,
                podcastID: feedURL,
                fileStore: transcriptFileStore,
                context: context
            )
        }
        let base = Date(timeIntervalSince1970: 1_780_400_000)
        insertDeferredRecord(
            kind: .capExceeded,
            episodeID: capEpisodeID,
            podcastID: feedURL,
            updatedAt: base.addingTimeInterval(10),
            context: context
        )
        insertDeferredRecord(
            kind: .insufficientSeconds,
            episodeID: needsMinutesEpisodeID,
            podcastID: feedURL,
            updatedAt: base,
            context: context
        )
        try context.save()

        let appModel = OpenCastAppModel(
            library: LibraryStore(localCache: localCache),
            transcriptions: EpisodeTranscriptionStore(fileStore: transcriptFileStore),
            transcriptAnalyses: transcriptAnalyses,
            allowsAutomaticFeedRefresh: false
        )
        await appModel.library.load(modelContext: context)
        appModel.transcriptions.load(modelContext: context)
        appModel.transcriptAnalyses.load(modelContext: context)
        appModel.retryDeferredTranscriptAnalyses(modelContext: context, trigger: .launch)

        // The load demoted both inherited deferrals to plain failures, so
        // the launch sweep found nothing to re-upload.
        try? await Task.sleep(for: .milliseconds(150))
        #expect(client.requests.isEmpty)
        #expect(!transcriptAnalyses.hasAcknowledgedGenerateDisclosure)
        #expect(transcriptAnalyses.capDeferredEpisodeIDs.isEmpty)
        #expect(transcriptAnalyses.insufficientSecondsDeferredEpisodeIDs.isEmpty)
        for episodeID in [capEpisodeID, needsMinutesEpisodeID] {
            let record = try #require(transcriptAnalyses.record(for: episodeID))
            #expect(record.state == .failed)
            #expect(record.failureKind == .generic)
        }
    }

    @Test("The disclosure acknowledgement persists across loads and keeps manual deferrals retryable")
    func acknowledgementPersistsAcrossLoads() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let store = EpisodeTranscriptAnalysisStore(
            client: FakeEpisodeTranscriptAnalysisClient(),
            fileStore: EpisodeTranscriptAnalysisFileStore(baseDirectory: temporaryDirectory)
        )
        #expect(!store.hasAcknowledgedGenerateDisclosure)
        store.acknowledgeGenerateDisclosure(modelContext: context)
        #expect(store.hasAcknowledgedGenerateDisclosure)
        insertDeferredRecord(
            kind: .insufficientSeconds,
            episodeID: "consent-kept",
            podcastID: "https://example.com/consent-kept.xml",
            updatedAt: .now,
            context: context
        )
        try context.save()

        let reloadedStore = EpisodeTranscriptAnalysisStore(
            client: FakeEpisodeTranscriptAnalysisClient(),
            fileStore: EpisodeTranscriptAnalysisFileStore(baseDirectory: temporaryDirectory)
        )
        reloadedStore.load(modelContext: context)

        #expect(reloadedStore.hasAcknowledgedGenerateDisclosure)
        #expect(reloadedStore.record(for: "consent-kept")?.failureKind == .insufficientSeconds)
        #expect(reloadedStore.insufficientSecondsDeferredEpisodeIDs == ["consent-kept"])
    }

    @Test("Episode detail snapshot threads the creator chapters URL")
    func episodeDetailSnapshotThreadsChaptersURL() async throws {
        let cache = SQLiteLocalLibraryCacheStore.inMemory()
        let feedURL = URL(string: "https://example.com/chaptered-cache.xml")!
        let snapshot = try RSSFeedParser().parse(
            data: Data(
                """
                <?xml version="1.0" encoding="utf-8"?>
                <rss version="2.0">
                  <channel>
                    <title>Chaptered Cache Show</title>
                    <item>
                      <title>With Chapters</title>
                      <guid>cache-chaptered-1</guid>
                      <podcast:chapters url="https://example.com/chapters/cache-1.json" type="application/json+chapters" />
                      <enclosure url="https://example.com/audio/cache-1.mp3" type="audio/mpeg" />
                    </item>
                    <item>
                      <title>Without Chapters</title>
                      <guid>cache-chaptered-2</guid>
                      <enclosure url="https://example.com/audio/cache-2.mp3" type="audio/mpeg" />
                    </item>
                  </channel>
                </rss>
                """.utf8
            ),
            feedURL: feedURL
        )
        try await cache.upsertCache(from: snapshot, refreshedAt: .now)

        let chaptered = try #require(
            await cache.episodeDetail(episodeID: snapshot.episodes[0].id.rawValue)
        )
        #expect(chaptered.chaptersURL == "https://example.com/chapters/cache-1.json")
        let plain = try #require(
            await cache.episodeDetail(episodeID: snapshot.episodes[1].id.rawValue)
        )
        #expect(plain.chaptersURL == nil)
    }

    // MARK: - Fixtures

    private func makeTranscriptDocument(
        episodeID: String,
        podcastID: String = "https://example.com/feed.xml",
        updatedAt: Date = Date(timeIntervalSince1970: 1_780_000_000)
    ) -> EpisodeTranscriptDocument {
        let segments = [
            OpenCastTranscriptSegment(
                id: 0,
                start: 0,
                end: 5,
                text: "Welcome back to the show.",
                avgLogProbability: -0.1,
                noSpeechProbability: 0.01
            ),
            OpenCastTranscriptSegment(
                id: 1,
                start: 5,
                end: 12,
                text: "This episode is brought to you by Example Sponsor.",
                avgLogProbability: -0.1,
                noSpeechProbability: 0.01
            )
        ]

        return EpisodeTranscriptDocument(
            schemaVersion: 1,
            episodeID: episodeID,
            podcastID: podcastID,
            sourceAudioURL: "https://example.com/\(episodeID).mp3",
            sourceFileByteCount: 987_654_321,
            sourceFileSHA256: "source-sha",
            modelIdentifier: "model",
            modelVersion: "v1",
            modelTreeSHA256: "tree-sha",
            languageCode: "en",
            audioDuration: 16,
            checkpoints: [],
            segments: segments,
            text: segments.map(\.text).joined(separator: " "),
            timings: EpisodeTranscriptTimings(),
            createdAt: updatedAt.addingTimeInterval(-10),
            updatedAt: updatedAt
        )
    }

    private func seedCompletedTranscript(
        episodeID: String,
        podcastID: String,
        fileStore: EpisodeTranscriptFileStore,
        context: ModelContext
    ) throws {
        let document = makeTranscriptDocument(episodeID: episodeID, podcastID: podcastID)
        let fingerprint = fileStore.fingerprint(
            sourceFileSHA256: document.sourceFileSHA256,
            modelIdentifier: document.modelIdentifier,
            modelVersion: document.modelVersion,
            modelTreeSHA256: document.modelTreeSHA256
        )
        let relativePath = fileStore.relativePath(episodeID: episodeID, fingerprint: fingerprint)
        try fileStore.write(document, relativePath: relativePath)
        context.insert(EpisodeTranscriptRecord(
            episodeID: episodeID,
            podcastID: podcastID,
            sourceAudioURL: document.sourceAudioURL,
            sourceFileByteCount: document.sourceFileByteCount,
            sourceFileSHA256: document.sourceFileSHA256,
            modelIdentifier: document.modelIdentifier,
            modelVersion: document.modelVersion,
            modelTreeSHA256: document.modelTreeSHA256,
            languageCode: document.languageCode,
            state: .completed,
            audioDuration: document.audioDuration,
            completedDuration: document.audioDuration,
            checkpointCount: document.checkpoints.count,
            transcriptRelativePath: relativePath,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt
        ))
    }

    private func insertCapDeferredRecord(
        episodeID: String,
        podcastID: String,
        updatedAt: Date,
        context: ModelContext
    ) {
        insertDeferredRecord(
            kind: .capExceeded,
            episodeID: episodeID,
            podcastID: podcastID,
            updatedAt: updatedAt,
            context: context
        )
    }

    private func insertDeferredRecord(
        kind: EpisodeAnalysisFailureKind,
        episodeID: String,
        podcastID: String,
        updatedAt: Date,
        context: ModelContext
    ) {
        let record = EpisodeTranscriptAnalysisRecord(
            episodeID: episodeID,
            podcastID: podcastID,
            state: .failed,
            errorMessage: "Deferred by the worker.",
            updatedAt: updatedAt
        )
        record.failureKind = kind
        context.insert(record)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "OpenCastTranscriptAnalysisTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// One-shot barrier: `enter()` parks callers until `open()`, and
/// `waitUntilEntered()` lets the test resume only once a caller is parked —
/// the deterministic "suspended mid-await" moment.
private actor SuspensionGate {
    private var isOpen = false
    private var hasEntered = false
    private var openWaiters: [CheckedContinuation<Void, Never>] = []
    private var enterWaiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        hasEntered = true
        for waiter in enterWaiters {
            waiter.resume()
        }
        enterWaiters.removeAll()
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { openWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !hasEntered else {
            return
        }
        await withCheckedContinuation { enterWaiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in openWaiters {
            waiter.resume()
        }
        openWaiters.removeAll()
    }
}

private final class GatedEpisodeTranscriptAnalysisClient: EpisodeTranscriptAnalysisClient, @unchecked Sendable {
    private let gate: SuspensionGate

    init(gate: SuspensionGate) {
        self.gate = gate
    }

    func analyze(_ request: EpisodeTranscriptAnalysisAPIRequest) async throws -> EpisodeTranscriptAnalysisSubmitOutcome {
        await gate.enter()
        return .completed(EpisodeTranscriptAnalysisAPIResponse(
            schemaVersion: 1,
            requestID: request.requestID,
            model: "gemini-3.5-flash",
            policy: EpisodeTranscriptAnalysisContract.expectedPolicy,
            chapters: [],
            summary: nil,
            warnings: [],
            usage: nil
        ))
    }

    func pollJob(id: String) async throws -> EpisodeTranscriptAnalysisJobPollOutcome {
        throw EpisodeTranscriptAnalysisError.clientDisabled
    }
}

private final class ThrowingEpisodeTranscriptAnalysisClient: EpisodeTranscriptAnalysisClient, @unchecked Sendable {
    var error: Error?
    private(set) var analyzeCallCount = 0

    init(error: Error?) {
        self.error = error
    }

    func analyze(_ request: EpisodeTranscriptAnalysisAPIRequest) async throws -> EpisodeTranscriptAnalysisSubmitOutcome {
        analyzeCallCount += 1
        if let error {
            throw error
        }

        return .completed(EpisodeTranscriptAnalysisAPIResponse(
            schemaVersion: 1,
            requestID: request.requestID,
            model: "gemini-3.5-flash",
            policy: EpisodeTranscriptAnalysisContract.expectedPolicy,
            chapters: [],
            summary: nil,
            warnings: [],
            usage: nil
        ))
    }

    func pollJob(id: String) async throws -> EpisodeTranscriptAnalysisJobPollOutcome {
        throw EpisodeTranscriptAnalysisError.clientDisabled
    }
}

private final class FakeEpisodeTranscriptAnalysisClient: EpisodeTranscriptAnalysisClient, @unchecked Sendable {
    private(set) var requests: [EpisodeTranscriptAnalysisAPIRequest] = []
    var policy = EpisodeTranscriptAnalysisContract.expectedPolicy

    var lastRequest: EpisodeTranscriptAnalysisAPIRequest? {
        requests.last
    }

    func analyze(_ request: EpisodeTranscriptAnalysisAPIRequest) async throws -> EpisodeTranscriptAnalysisSubmitOutcome {
        requests.append(request)
        return .completed(EpisodeTranscriptAnalysisAPIResponse(
            schemaVersion: 1,
            requestID: request.requestID,
            model: "gemini-3.5-flash",
            policy: policy,
            chapters: [
                EpisodeTranscriptAnalysisAPIChapter(
                    title: "Welcome",
                    startSegmentID: 0,
                    endSegmentID: 0,
                    startTime: 0,
                    endTime: 5,
                    confidence: 0.9
                ),
                EpisodeTranscriptAnalysisAPIChapter(
                    title: "The Sponsor Read",
                    startSegmentID: 1,
                    endSegmentID: 1,
                    startTime: 5,
                    endTime: 12,
                    confidence: 0.8
                )
            ],
            summary: EpisodeTranscriptAnalysisAPISummary(
                summary: "A warm welcome followed by a sponsor read.",
                oneLineDescription: "A short test episode",
                claims: [
                    EpisodeTranscriptAnalysisAPIClaim(
                        text: "The host welcomes listeners back.",
                        evidenceSegmentID: 0
                    )
                ]
            ),
            warnings: [],
            usage: EpisodeTranscriptAnalysisAPIUsage(
                promptTokenCount: 100,
                candidatesTokenCount: 20,
                thoughtsTokenCount: 30,
                totalTokenCount: 150
            )
        ))
    }

    func pollJob(id: String) async throws -> EpisodeTranscriptAnalysisJobPollOutcome {
        throw EpisodeTranscriptAnalysisError.clientDisabled
    }
}
