import Foundation
import OpenCastTranscription
import SwiftData
import Testing
@testable import OpenCast

@MainActor
@Suite("Episode ad analysis store")
struct EpisodeAdAnalysisStoreTests {
    @Test("Creates ad analysis record and document from client response")
    func createsAdAnalysisRecordAndDocumentFromClientResponse() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let client = FakeEpisodeAdAnalysisClient()
        let fileStore = EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        let store = EpisodeAdAnalysisStore(client: client, fileStore: fileStore)
        let transcript = makeTranscriptDocument(episodeID: "ad-create")

        store.startAnalysis(transcript: transcript, modelContext: context)

        #expect(await waitUntil {
            store.record(for: transcript.episodeID)?.state == .completed
        })
        let record = try #require(store.record(for: transcript.episodeID))
        let document = try #require(store.document(for: transcript.episodeID))
        let request = try #require(client.lastRequest)
        let encodedRequest = try encodedJSONString(request)
        #expect(record.spanCount == 1)
        #expect(record.transcriptState == .completed)
        #expect(document.spans.first?.label == "Example Sponsor")
        #expect(document.transcriptSegmentCount == transcript.segments.count)
        #expect(document.transcriptState == .completed)
        #expect(request.transcript.state == "completed")
        #expect(request.asyncSupported == true)
        #expect(encodedRequest.contains(#""async_supported":true"#))
        #expect(request.segments.map(\.text) == transcript.segments.map(\.text))
        #expect(encodedRequest.contains(transcript.segments[1].text))
        #expect(encodedRequest.contains(request.transcript.fingerprint))
        #expect(!encodedRequest.contains(transcript.sourceAudioURL))
        #expect(!encodedRequest.contains(transcript.sourceFileSHA256))
        #expect(!encodedRequest.contains(String(transcript.sourceFileByteCount)))
        #expect(!encodedRequest.contains("\"sourceAudioURL\""))
        #expect(!encodedRequest.contains("\"sourceFileSHA256\""))
        #expect(!encodedRequest.contains("\"sourceFileByteCount\""))
        #expect(!encodedRequest.contains("\"source_audio_url\""))
        #expect(!encodedRequest.contains("\"source_file_sha256\""))
        #expect(!encodedRequest.contains("\"source_file_byte_count\""))
    }

    @Test("Normalizes tiny transcript overlap before client request")
    func normalizesTinyTranscriptOverlapBeforeClientRequest() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let client = FakeEpisodeAdAnalysisClient()
        let store = EpisodeAdAnalysisStore(
            client: client,
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        )
        var transcript = makeTranscriptDocument(episodeID: "ad-overlap")
        transcript.segments = [
            OpenCastTranscriptSegment(
                id: 1922,
                start: 8755.3935546875,
                end: 8760.3935546875,
                text: "Only that the goal is to tamper with numerical results.",
                avgLogProbability: -0.1,
                noSpeechProbability: 0.01
            ),
            OpenCastTranscriptSegment(
                id: 1923,
                start: 8760.3916015625,
                end: 8767.3916015625,
                text: "not unauthorized access, not malware propagation, or other common malware objectives.",
                avgLogProbability: -0.1,
                noSpeechProbability: 0.01
            )
        ]
        transcript.text = transcript.segments.map(\.text).joined(separator: " ")

        store.startAnalysis(transcript: transcript, modelContext: context)

        #expect(await waitUntil {
            store.record(for: transcript.episodeID)?.state == .completed
        })
        let request = try #require(client.lastRequest)
        #expect(request.transcript.segmentCount == 2)
        #expect(request.segments.map(\.id) == [0, 1])
        #expect(request.segments[0].end == 8760.3935546875)
        #expect(request.segments[1].start == 8760.3935546875)
        #expect(request.segments[1].end == 8767.3916015625)
    }

    @Test("Drops blank transcript segments before client request")
    func dropsBlankTranscriptSegmentsBeforeClientRequest() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let client = FakeEpisodeAdAnalysisClient()
        let fileStore = EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        let store = EpisodeAdAnalysisStore(client: client, fileStore: fileStore)
        var transcript = makeTranscriptDocument(episodeID: "ad-blank-segments")
        transcript.segments = [
            OpenCastTranscriptSegment(
                id: 40,
                start: 0,
                end: 4,
                text: "  Welcome back to the show.  ",
                avgLogProbability: -0.1,
                noSpeechProbability: 0.01
            ),
            OpenCastTranscriptSegment(
                id: 41,
                start: 4,
                end: 5,
                text: "   ",
                avgLogProbability: -0.1,
                noSpeechProbability: 0.01
            ),
            OpenCastTranscriptSegment(
                id: 42,
                start: 5,
                end: 6,
                text: "\n\t",
                avgLogProbability: -0.1,
                noSpeechProbability: 0.01
            ),
            OpenCastTranscriptSegment(
                id: 43,
                start: 6,
                end: 11,
                text: "Back to the episode.",
                avgLogProbability: -0.1,
                noSpeechProbability: 0.01
            )
        ]
        transcript.text = transcript.segments.map(\.text).joined(separator: " ")

        store.startAnalysis(transcript: transcript, modelContext: context)

        #expect(await waitUntil {
            store.record(for: transcript.episodeID)?.state == .completed
        })
        let record = try #require(store.record(for: transcript.episodeID))
        let document = try #require(store.document(for: transcript.episodeID))
        let request = try #require(client.lastRequest)
        #expect(request.transcript.segmentCount == 2)
        #expect(request.segments.map(\.id) == [0, 1])
        #expect(request.segments.map(\.text) == [
            "Welcome back to the show.",
            "Back to the episode."
        ])
        #expect(record.transcriptSegmentCount == 2)
        #expect(document.transcriptSegmentCount == 2)
        #expect(document.transcriptFingerprint == fileStore.transcriptFingerprint(for: transcript))
    }

    @Test("Blank-only transcript is unavailable for analysis")
    func blankOnlyTranscriptIsUnavailableForAnalysis() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let client = FakeEpisodeAdAnalysisClient()
        let store = EpisodeAdAnalysisStore(
            client: client,
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        )
        var transcript = makeTranscriptDocument(episodeID: "ad-blank-only")
        transcript.segments = [
            OpenCastTranscriptSegment(
                id: 80,
                start: 0,
                end: 2,
                text: " \n\t ",
                avgLogProbability: -0.1,
                noSpeechProbability: 0.01
            )
        ]
        transcript.text = transcript.segments.map(\.text).joined(separator: " ")

        if case .unavailable(let message) = store.jobState(for: transcript) {
            #expect(message == "Transcript has no segments.")
        } else {
            Issue.record("Expected unavailable state for blank-only transcript.")
        }

        store.startAnalysis(transcript: transcript, modelContext: context)
        #expect(await waitUntil {
            !store.hasActiveJob
        })

        #expect(client.lastRequest == nil)
        #expect(store.record(for: transcript.episodeID) == nil)
        #expect(store.lastErrorMessage(for: transcript.episodeID) == EpisodeAdAnalysisError.transcriptNotCompleted.localizedDescription)
    }

    @Test("Unavailable backend hides analysis start and avoids client calls")
    func unavailableBackendHidesAnalysisStartAndAvoidsClientCalls() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let client = FakeEpisodeAdAnalysisClient()
        let store = EpisodeAdAnalysisStore(
            client: client,
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory),
            analysisUnavailableMessage: "Promo/ad analysis is not configured on this device."
        )
        let transcript = makeTranscriptDocument(episodeID: "ad-unavailable")

        #expect(!store.canStartAnalysis)
        if case .unavailable(let message) = store.jobState(for: transcript) {
            #expect(message == "Promo/ad analysis is not configured on this device.")
        } else {
            Issue.record("Expected unavailable state.")
        }

        store.startAnalysis(transcript: transcript, modelContext: context)
        try? await Task.sleep(for: .milliseconds(20))

        #expect(client.lastRequest == nil)
        #expect(store.record(for: transcript.episodeID) == nil)
        #expect(!store.hasActiveJob)
        #expect(store.lastErrorMessage(for: transcript.episodeID) == "Promo/ad analysis is not configured on this device.")
    }

    @Test("App model refuses ad analysis for non-completed transcript records")
    func appModelRefusesAdAnalysisForNonCompletedTranscriptRecords() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let transcriptFileStore = EpisodeTranscriptFileStore(baseDirectory: temporaryDirectory)
        let transcriptions = EpisodeTranscriptionStore(fileStore: transcriptFileStore)
        let client = FakeEpisodeAdAnalysisClient()
        let adAnalyses = EpisodeAdAnalysisStore(
            client: client,
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        )
        let appModel = OpenCastAppModel(
            transcriptions: transcriptions,
            adAnalyses: adAnalyses,
            allowsAutomaticFeedRefresh: false
        )
        let transcript = makeTranscriptDocument(episodeID: "ad-incomplete-transcript")

        _ = try writeTranscript(
            transcript,
            fileStore: transcriptFileStore,
            modelContext: context,
            state: .interrupted
        )
        transcriptions.load(modelContext: context)

        if case .unavailable(let message) = adAnalyses.jobState(
            for: transcript,
            transcriptState: transcriptions.record(for: transcript.episodeID)?.state
        ) {
            #expect(message == EpisodeAdAnalysisError.transcriptNotCompleted.localizedDescription)
        } else {
            Issue.record("Expected unavailable state for incomplete transcript.")
        }

        appModel.analyzeEpisodeTranscript(transcript, modelContext: context)
        try? await Task.sleep(for: .milliseconds(20))

        #expect(client.lastRequest == nil)
        #expect(adAnalyses.record(for: transcript.episodeID) == nil)
        #expect(!adAnalyses.hasActiveJob)
        #expect(adAnalyses.lastErrorMessage(for: transcript.episodeID) == EpisodeAdAnalysisError.transcriptNotCompleted.localizedDescription)
    }

    @Test("Active analysis reports running and blocks another analysis")
    func activeAnalysisReportsRunningAndBlocksAnotherAnalysis() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let client = HangingEpisodeAdAnalysisClient()
        let store = EpisodeAdAnalysisStore(
            client: client,
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        )
        let firstTranscript = makeTranscriptDocument(episodeID: "ad-active-first")
        let secondTranscript = makeTranscriptDocument(episodeID: "ad-active-second")

        store.startAnalysis(transcript: firstTranscript, modelContext: context)

        #expect(store.hasActiveJob)
        if case .running = store.jobState(for: firstTranscript) {
        } else {
            Issue.record("Expected first analysis to be running.")
        }

        store.startAnalysis(transcript: secondTranscript, modelContext: context)

        #expect(store.record(for: secondTranscript.episodeID) == nil)
        #expect(store.lastErrorMessage(for: secondTranscript.episodeID) == EpisodeAdAnalysisError.anotherJobActive.localizedDescription)

        await client.release()

        #expect(await waitUntil {
            store.record(for: firstTranscript.episodeID)?.state == .completed
        })
        let requestCount = await client.currentRequestCount()
        #expect(requestCount == 1)
        #expect(!store.hasActiveJob)
    }

    @Test("An active job never marks other episodes as running")
    func activeJobNeverMarksOtherEpisodesRunning() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let client = HangingEpisodeAdAnalysisClient()
        let store = EpisodeAdAnalysisStore(
            client: client,
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: try makeTemporaryDirectory())
        )
        let runningTranscript = makeTranscriptDocument(episodeID: "ad-running-first")
        let otherTranscript = makeTranscriptDocument(episodeID: "ad-idle-second")

        store.startAnalysis(transcript: runningTranscript, modelContext: context)
        #expect(store.isRunning(for: runningTranscript.episodeID))

        // The uninvolved episode was never queued: while the first job is in
        // flight it must offer detection, not report that run as its own.
        #expect(!store.isRunning(for: otherTranscript.episodeID))
        if case .ready = store.jobState(for: otherTranscript) {
        } else {
            Issue.record("Expected the uninvolved episode to stay ready, got \(store.jobState(for: otherTranscript))")
        }

        await client.release()

        #expect(await waitUntil {
            !store.hasActiveJob
        })
    }

    @Test("Store reports running while normalization and fingerprint preparation is held")
    func reportsRunningDuringHeldPreparation() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let gate = AsyncTestGate()
        let client = FakeEpisodeAdAnalysisClient()
        let store = EpisodeAdAnalysisStore(
            client: client,
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: try makeTemporaryDirectory()),
            preparationGate: {
                await gate.wait()
            }
        )
        let transcript = makeTranscriptDocument(episodeID: "ad-held-preparation")

        store.startAnalysis(transcript: transcript, modelContext: context)

        #expect(store.hasActiveJob)
        #expect(store.record(for: transcript.episodeID) == nil)
        if case .running = store.jobState(for: transcript) {
        } else {
            Issue.record("Expected running while preparation is held.")
        }
        #expect(client.lastRequest == nil)

        await gate.release()

        #expect(await waitUntil {
            store.record(for: transcript.episodeID)?.state == .completed
        })
    }

    @Test("Cancellation during held preparation performs no request or persistence")
    func cancellationDuringHeldPreparation() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let gate = AsyncTestGate()
        let client = FakeEpisodeAdAnalysisClient()
        let store = EpisodeAdAnalysisStore(
            client: client,
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: try makeTemporaryDirectory()),
            preparationGate: {
                await gate.wait()
            }
        )
        let transcript = makeTranscriptDocument(episodeID: "ad-cancelled-preparation")

        store.startAnalysis(transcript: transcript, modelContext: context)
        store.cancelActiveJob()
        await gate.release()

        #expect(await waitUntil {
            !store.hasActiveJob
        })
        #expect(store.record(for: transcript.episodeID) == nil)
        #expect(client.lastRequest == nil)
    }

    @Test("Preparation failure clears running state and surfaces the error")
    func preparationFailureSurfacesError() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let gate = AsyncTestGate()
        let client = FakeEpisodeAdAnalysisClient()
        let store = EpisodeAdAnalysisStore(
            client: client,
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: try makeTemporaryDirectory()),
            preparationGate: {
                await gate.wait()
                throw EpisodeAdAnalysisError.transcriptNotCompleted
            }
        )
        let transcript = makeTranscriptDocument(episodeID: "ad-failed-preparation")

        store.startAnalysis(transcript: transcript, modelContext: context)
        #expect(store.hasActiveJob)
        await gate.release()

        #expect(await waitUntil {
            !store.hasActiveJob
        })
        #expect(
            store.lastErrorMessage(for: transcript.episodeID)
                == EpisodeAdAnalysisError.transcriptNotCompleted.localizedDescription
        )
        #expect(store.record(for: transcript.episodeID) == nil)
        #expect(client.lastRequest == nil)
    }

    @Test("Nuke cancels active analysis and removes running record")
    func nukeCancelsActiveAnalysisAndRemovesRunningRecord() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let client = HangingEpisodeAdAnalysisClient()
        let fileStore = EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        let store = EpisodeAdAnalysisStore(client: client, fileStore: fileStore)
        let transcript = makeTranscriptDocument(episodeID: "ad-active-nuke")

        store.startAnalysis(transcript: transcript, modelContext: context)
        #expect(store.hasActiveJob)

        try await store.nukeAllAnalyses(modelContext: context)

        #expect(!store.hasActiveJob)
        #expect(store.records.isEmpty)
        #expect(try context.fetch(FetchDescriptor<EpisodeAdAnalysisRecord>()).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileStore.analysesDirectory.path))
    }

    @Test("Ad analysis record is local-only but included in full schema")
    func adAnalysisRecordIsLocalOnlyButIncludedInFullSchema() {
        #expect(OpenCastModelContainerFactory.localSchema.entitiesByName["EpisodeAdAnalysisRecord"] != nil)
        #expect(OpenCastModelContainerFactory.fullSchema.entitiesByName["EpisodeAdAnalysisRecord"] != nil)
        #expect(OpenCastModelContainerFactory.syncedSchema.entitiesByName["EpisodeAdAnalysisRecord"] == nil)
    }

    @Test("Marks completed analysis stale when transcript fingerprint inputs change")
    func marksCompletedAnalysisStaleWhenTranscriptFingerprintInputsChange() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let store = EpisodeAdAnalysisStore(
            client: FakeEpisodeAdAnalysisClient(),
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        )
        let transcript = makeTranscriptDocument(episodeID: "ad-stale")

        store.startAnalysis(transcript: transcript, modelContext: context)

        #expect(await waitUntil {
            store.record(for: transcript.episodeID)?.state == .completed
        })
        let updatedTranscript = makeTranscriptDocument(
            episodeID: "ad-stale",
            updatedAt: transcript.updatedAt.addingTimeInterval(30),
            extraSegmentText: "new segment"
        )

        if case .completed(_, let isStale) = store.jobState(for: updatedTranscript) {
            #expect(isStale)
        } else {
            Issue.record("Expected completed stale state.")
        }
    }

    @Test("Marks completed analysis stale when only transcript text changes")
    func marksCompletedAnalysisStaleWhenOnlyTranscriptTextChanges() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let store = EpisodeAdAnalysisStore(
            client: FakeEpisodeAdAnalysisClient(),
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        )
        let transcript = makeTranscriptDocument(episodeID: "ad-fingerprint-stale")

        await startAndWait(store: store, transcript: transcript, modelContext: context)
        let updatedTranscript = makeTranscriptDocument(
            episodeID: "ad-fingerprint-stale",
            updatedAt: transcript.updatedAt,
            sponsorSegmentText: "Different sponsor copy with the same segment count."
        )

        if case .completed(_, let isStale) = store.jobState(for: updatedTranscript) {
            #expect(isStale)
        } else {
            Issue.record("Expected completed stale state.")
        }
    }

    @Test("Marks completed analysis stale when stored transcript state is not completed")
    func marksCompletedAnalysisStaleWhenStoredTranscriptStateIsNotCompleted() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let store = EpisodeAdAnalysisStore(
            client: FakeEpisodeAdAnalysisClient(),
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        )
        let transcript = makeTranscriptDocument(episodeID: "ad-state-stale")

        await startAndWait(store: store, transcript: transcript, modelContext: context)
        let record = try #require(store.record(for: transcript.episodeID))
        record.transcriptState = .interrupted

        if case .completed(_, let isStale) = store.jobState(for: transcript) {
            #expect(isStale)
        } else {
            Issue.record("Expected completed stale state.")
        }
    }

    @Test("Marks completed ads_only analysis outdated and re-run overwrites it")
    func marksCompletedAdsOnlyAnalysisOutdatedAndRerunOverwrites() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let store = EpisodeAdAnalysisStore(
            client: FakeEpisodeAdAnalysisClient(),
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        )
        let transcript = makeTranscriptDocument(episodeID: "ad-policy-stale")

        await startAndWait(store: store, transcript: transcript, modelContext: context)
        let record = try #require(store.record(for: transcript.episodeID))
        // Rewrite the stored analysis as a legacy ads_only result whose
        // transcript inputs are still perfectly current.
        record.policy = "ads_only"
        var document = try #require(store.document(for: transcript.episodeID))
        document.policy = "ads_only"
        let relativePath = try #require(record.analysisRelativePath)
        try EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
            .write(document, relativePath: relativePath)

        if case .completed(_, let isStale) = store.jobState(for: transcript) {
            #expect(isStale)
        } else {
            Issue.record("Expected completed stale state for ads_only policy.")
        }
        #expect(!store.isCurrentAnalysisDocument(document, for: transcript))

        // A manual re-run overwrites the outdated document and clears staleness.
        await startAndWait(store: store, transcript: transcript, modelContext: context)
        if case .completed(_, let isStale) = store.jobState(for: transcript) {
            #expect(!isStale)
        } else {
            Issue.record("Expected completed current state after re-run.")
        }
        let rerunDocument = try #require(store.document(for: transcript.episodeID))
        #expect(rerunDocument.policy == EpisodeAdAnalysisContract.expectedPolicy)
        #expect(store.isCurrentAnalysisDocument(rerunDocument, for: transcript))
    }

    @Test("Current document check requires matching fingerprint metadata")
    func currentDocumentCheckRequiresMatchingFingerprintMetadata() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let store = EpisodeAdAnalysisStore(
            client: FakeEpisodeAdAnalysisClient(),
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        )
        let transcript = makeTranscriptDocument(episodeID: "ad-current-document")

        await startAndWait(store: store, transcript: transcript, modelContext: context)
        let analysisDocument = try #require(store.document(for: transcript.episodeID))

        #expect(store.isCurrentAnalysisDocument(analysisDocument, for: transcript))
        var interruptedStateDocument = analysisDocument
        interruptedStateDocument.transcriptState = .interrupted
        #expect(!store.isCurrentAnalysisDocument(interruptedStateDocument, for: transcript))

        let textChangedTranscript = makeTranscriptDocument(
            episodeID: transcript.episodeID,
            updatedAt: transcript.updatedAt,
            sponsorSegmentText: "Same timing and segment count but different words."
        )
        #expect(!store.isCurrentAnalysisDocument(analysisDocument, for: textChangedTranscript))

        let updatedTranscript = makeTranscriptDocument(
            episodeID: transcript.episodeID,
            updatedAt: transcript.updatedAt.addingTimeInterval(30)
        )
        #expect(!store.isCurrentAnalysisDocument(analysisDocument, for: updatedTranscript))

        let segmentCountChangedTranscript = makeTranscriptDocument(
            episodeID: transcript.episodeID,
            updatedAt: transcript.updatedAt,
            extraSegmentText: "Extra transcript segment."
        )
        #expect(!store.isCurrentAnalysisDocument(analysisDocument, for: segmentCountChangedTranscript))
    }

    @Test("Deletes ad analysis record and sidecar")
    func deletesAdAnalysisRecordAndSidecar() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let fileStore = EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        let store = EpisodeAdAnalysisStore(
            client: FakeEpisodeAdAnalysisClient(),
            fileStore: fileStore
        )
        let transcript = makeTranscriptDocument(episodeID: "ad-delete")

        store.startAnalysis(transcript: transcript, modelContext: context)

        #expect(await waitUntil {
            store.record(for: transcript.episodeID)?.state == .completed
        })
        let relativePath = try #require(store.record(for: transcript.episodeID)?.analysisRelativePath)
        #expect(fileStore.documentExists(relativePath: relativePath))
        let orphanRelativePath = "\(EpisodeAdAnalysisFileStore.directoryName)/\(fileStore.safeStem(transcript.episodeID))/orphan.json"
        let orphanURL = fileStore.fileURL(relativePath: orphanRelativePath)
        try FileManager.default.createDirectory(
            at: orphanURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: orphanURL)
        #expect(fileStore.documentExists(relativePath: orphanRelativePath))

        store.deleteAnalysis(episodeID: transcript.episodeID, modelContext: context)

        #expect(store.record(for: transcript.episodeID) == nil)
        #expect(!fileStore.documentExists(relativePath: relativePath))
        #expect(!fileStore.documentExists(relativePath: orphanRelativePath))
    }

    @Test("App model transcript deletion removes transcript and ad analysis sidecars")
    func appModelTranscriptDeletionRemovesTranscriptAndAdAnalysisSidecars() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let transcriptFileStore = EpisodeTranscriptFileStore(baseDirectory: temporaryDirectory)
        let adAnalysisFileStore = EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        let transcriptions = EpisodeTranscriptionStore(fileStore: transcriptFileStore)
        let adAnalyses = EpisodeAdAnalysisStore(
            client: FakeEpisodeAdAnalysisClient(),
            fileStore: adAnalysisFileStore
        )
        let appModel = OpenCastAppModel(
            transcriptions: transcriptions,
            adAnalyses: adAnalyses,
            allowsAutomaticFeedRefresh: false
        )
        let transcript = makeTranscriptDocument(episodeID: "ad-app-delete-transcript")
        let transcriptRelativePath = try writeTranscript(
            transcript,
            fileStore: transcriptFileStore,
            modelContext: context
        )
        transcriptions.load(modelContext: context)
        await startAndWait(store: adAnalyses, transcript: transcript, modelContext: context)
        let analysisRelativePath = try #require(adAnalyses.record(for: transcript.episodeID)?.analysisRelativePath)
        #expect(transcriptFileStore.documentExists(relativePath: transcriptRelativePath))
        #expect(adAnalysisFileStore.documentExists(relativePath: analysisRelativePath))

        appModel.deleteEpisodeTranscript(episodeID: transcript.episodeID, modelContext: context)

        #expect(try context.fetch(FetchDescriptor<EpisodeTranscriptRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<EpisodeAdAnalysisRecord>()).isEmpty)
        #expect(!transcriptFileStore.documentExists(relativePath: transcriptRelativePath))
        #expect(!adAnalysisFileStore.documentExists(relativePath: analysisRelativePath))
        #expect(appModel.transcriptions.record(for: transcript.episodeID) == nil)
        #expect(appModel.adAnalyses.record(for: transcript.episodeID) == nil)
    }

    @Test("Deletes ad analyses for one podcast and preserves other podcasts")
    func deletesAdAnalysesForPodcast() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let fileStore = EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        let store = EpisodeAdAnalysisStore(
            client: FakeEpisodeAdAnalysisClient(),
            fileStore: fileStore
        )
        let firstTranscript = makeTranscriptDocument(
            episodeID: "ad-podcast-delete-1",
            podcastID: "https://example.com/delete.xml"
        )
        let secondTranscript = makeTranscriptDocument(
            episodeID: "ad-podcast-delete-2",
            podcastID: "https://example.com/delete.xml"
        )
        let preservedTranscript = makeTranscriptDocument(
            episodeID: "ad-podcast-preserved",
            podcastID: "https://example.com/preserved.xml"
        )

        await startAndWait(store: store, transcript: firstTranscript, modelContext: context)
        await startAndWait(store: store, transcript: secondTranscript, modelContext: context)
        await startAndWait(store: store, transcript: preservedTranscript, modelContext: context)
        let firstPath = try #require(store.record(for: firstTranscript.episodeID)?.analysisRelativePath)
        let secondPath = try #require(store.record(for: secondTranscript.episodeID)?.analysisRelativePath)
        let preservedPath = try #require(store.record(for: preservedTranscript.episodeID)?.analysisRelativePath)
        let orphanRelativePath = "\(EpisodeAdAnalysisFileStore.directoryName)/\(fileStore.safeStem(firstTranscript.episodeID))/orphan.json"
        let orphanURL = fileStore.fileURL(relativePath: orphanRelativePath)
        try FileManager.default.createDirectory(
            at: orphanURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: orphanURL)
        #expect(fileStore.documentExists(relativePath: orphanRelativePath))

        try store.deleteAnalyses(
            forPodcastID: "https://example.com/delete.xml",
            modelContext: context
        )

        #expect(store.record(for: firstTranscript.episodeID) == nil)
        #expect(store.record(for: secondTranscript.episodeID) == nil)
        #expect(store.record(for: preservedTranscript.episodeID)?.state == .completed)
        #expect(!fileStore.documentExists(relativePath: firstPath))
        #expect(!fileStore.documentExists(relativePath: secondPath))
        #expect(!fileStore.documentExists(relativePath: orphanRelativePath))
        #expect(fileStore.documentExists(relativePath: preservedPath))
    }

    @Test("App model unsubscribe removes transcript and ad analysis sidecars for podcast")
    func appModelUnsubscribeRemovesTranscriptAndAdAnalysisSidecarsForPodcast() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let transcriptFileStore = EpisodeTranscriptFileStore(baseDirectory: temporaryDirectory)
        let adAnalysisFileStore = EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        let transcriptions = EpisodeTranscriptionStore(fileStore: transcriptFileStore)
        let adAnalyses = EpisodeAdAnalysisStore(
            client: FakeEpisodeAdAnalysisClient(),
            fileStore: adAnalysisFileStore
        )
        let appModel = OpenCastAppModel(
            library: LibraryStore(localCache: SQLiteLocalLibraryCacheStore.inMemory()),
            transcriptions: transcriptions,
            adAnalyses: adAnalyses,
            allowsAutomaticFeedRefresh: false
        )
        let removedFeedURL = "https://example.com/app-unsubscribe-remove.xml"
        let keptFeedURL = "https://example.com/app-unsubscribe-keep.xml"
        let removedTranscript = makeTranscriptDocument(
            episodeID: "ad-app-unsubscribe-remove",
            podcastID: removedFeedURL
        )
        let keptTranscript = makeTranscriptDocument(
            episodeID: "ad-app-unsubscribe-keep",
            podcastID: keptFeedURL
        )
        let removedTranscriptPath = try writeTranscript(
            removedTranscript,
            fileStore: transcriptFileStore,
            modelContext: context
        )
        let keptTranscriptPath = try writeTranscript(
            keptTranscript,
            fileStore: transcriptFileStore,
            modelContext: context
        )
        transcriptions.load(modelContext: context)
        await startAndWait(store: adAnalyses, transcript: removedTranscript, modelContext: context)
        await startAndWait(store: adAnalyses, transcript: keptTranscript, modelContext: context)
        let removedAnalysisPath = try #require(adAnalyses.record(for: removedTranscript.episodeID)?.analysisRelativePath)
        let keptAnalysisPath = try #require(adAnalyses.record(for: keptTranscript.episodeID)?.analysisRelativePath)

        await appModel.unsubscribe(feedURL: removedFeedURL, modelContext: context)

        #expect(try context.fetch(FetchDescriptor<EpisodeTranscriptRecord>()).map(\.episodeID) == [keptTranscript.episodeID])
        #expect(try context.fetch(FetchDescriptor<EpisodeAdAnalysisRecord>()).map(\.episodeID) == [keptTranscript.episodeID])
        #expect(!transcriptFileStore.documentExists(relativePath: removedTranscriptPath))
        #expect(transcriptFileStore.documentExists(relativePath: keptTranscriptPath))
        #expect(!adAnalysisFileStore.documentExists(relativePath: removedAnalysisPath))
        #expect(adAnalysisFileStore.documentExists(relativePath: keptAnalysisPath))
        #expect(appModel.transcriptions.record(for: removedTranscript.episodeID) == nil)
        #expect(appModel.transcriptions.record(for: keptTranscript.episodeID)?.state == .completed)
        #expect(appModel.adAnalyses.record(for: removedTranscript.episodeID) == nil)
        #expect(appModel.adAnalyses.record(for: keptTranscript.episodeID)?.state == .completed)
    }

    @Test("Nuke removes all ad analysis records and sidecars")
    func nukeRemovesAllAdAnalysisRecordsAndSidecars() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let fileStore = EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        let store = EpisodeAdAnalysisStore(
            client: FakeEpisodeAdAnalysisClient(),
            fileStore: fileStore
        )
        let firstTranscript = makeTranscriptDocument(episodeID: "ad-nuke-1")
        let secondTranscript = makeTranscriptDocument(episodeID: "ad-nuke-2")

        await startAndWait(store: store, transcript: firstTranscript, modelContext: context)
        await startAndWait(store: store, transcript: secondTranscript, modelContext: context)
        #expect(FileManager.default.fileExists(atPath: fileStore.analysesDirectory.path))

        try await store.nukeAllAnalyses(modelContext: context)

        #expect(store.records.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileStore.analysesDirectory.path))
    }

    @Test("Load marks completed analysis failed when sidecar is missing")
    func loadMarksCompletedAnalysisFailedWhenSidecarIsMissing() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let fileStore = EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        let store = EpisodeAdAnalysisStore(
            client: FakeEpisodeAdAnalysisClient(),
            fileStore: fileStore
        )
        let transcript = makeTranscriptDocument(episodeID: "ad-missing-sidecar")

        await startAndWait(store: store, transcript: transcript, modelContext: context)
        let relativePath = try #require(store.record(for: transcript.episodeID)?.analysisRelativePath)
        try fileStore.delete(relativePath: relativePath)
        guard case .completed(_, isStale: true) = store.jobState(for: transcript) else {
            Issue.record("A completed analysis still requires its output document.")
            return
        }

        let reloadedStore = EpisodeAdAnalysisStore(
            client: FakeEpisodeAdAnalysisClient(),
            fileStore: fileStore
        )
        reloadedStore.load(modelContext: context)

        let record = try #require(reloadedStore.record(for: transcript.episodeID))
        #expect(record.state == .failed)
        #expect(record.errorMessage == "Promo/ad analysis document is missing.")
    }

    @Test("Validation exhaustion persists across relaunch, but explicit retry and changed inputs remain eligible")
    func validationReplayPersistence() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let files = EpisodeAdAnalysisFileStore(baseDirectory: try makeTemporaryDirectory())
        let client = ThrowingEpisodeAdAnalysisClient(error: EpisodeAdAnalysisHTTPError(
            statusCode: 422, code: "ad_analysis_incomplete", detail: nil,
            failure: .init(category: .validationExhausted, retryDisposition: .explicitRetry, policyRevision: "revision-a")))
        client.revision = "revision-a"
        let store = EpisodeAdAnalysisStore(client: client, fileStore: files)
        let transcript = makeTranscriptDocument(episodeID: "replay-persistence")
        store.startAnalysis(transcript: transcript, modelContext: context)
        #expect(await waitUntil { store.record(for: transcript.episodeID)?.state == .failed })
        let reloaded = EpisodeAdAnalysisStore(client: client, fileStore: files)
        reloaded.load(modelContext: context)
        #expect(try await reloaded.automaticReplayError(for: transcript) != nil)
        var reimported = transcript
        reimported.updatedAt = .now
        #expect(try await reloaded.automaticReplayError(for: reimported) != nil)
        var changed = transcript
        changed.sourceFileSHA256 = "different-recording"
        #expect(try await reloaded.automaticReplayError(for: changed) == nil)
        changed = transcript
        changed.segments[0].text += " New source text."
        #expect(try await reloaded.automaticReplayError(for: changed) == nil)
        client.revision = "revision-b"
        #expect(try await reloaded.automaticReplayError(for: transcript) == nil)
        client.revision = "revision-a"
        reloaded.startAnalysis(transcript: transcript, retryFailed: false, modelContext: context)
        #expect(await waitUntil { !reloaded.isRunning(for: transcript.episodeID) })
        #expect(client.calls == 1)
        client.error = nil
        reloaded.startAnalysis(transcript: transcript, modelContext: context)
        #expect(await waitUntil { reloaded.record(for: transcript.episodeID)?.state == .completed })
        #expect(client.calls == 2)
        #expect(client.lastRetryFailed == true)
        #expect(try await reloaded.automaticReplayError(for: transcript) == nil)
    }

    @Test("A failed replacement preserves the last valid ad document")
    func replacementFailurePreservesGoodAnalysis() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let files = EpisodeAdAnalysisFileStore(baseDirectory: try makeTemporaryDirectory())
        let client = ThrowingEpisodeAdAnalysisClient(error: nil)
        let store = EpisodeAdAnalysisStore(client: client, fileStore: files)
        let transcript = makeTranscriptDocument(episodeID: "retain-good-analysis")
        await startAndWait(store: store, transcript: transcript, modelContext: context)
        let original = try #require(store.document(for: transcript.episodeID))
        client.error = EpisodeAdAnalysisHTTPError(statusCode: 422, code: "ad_analysis_incomplete", detail: nil)
        store.startAnalysis(transcript: transcript, modelContext: context)
        #expect(await waitUntil { client.calls == 2 && !store.isRunning(for: transcript.episodeID) })
        #expect(store.record(for: transcript.episodeID)?.state == .completed)
        #expect(store.document(for: transcript.episodeID) == original)
        #expect(store.lastErrorMessage(for: transcript.episodeID) != nil)
    }

    @Test("Cap rejections thread a typed failure kind onto the record")
    func capRejectionThreadsFailureKindOntoRecord() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let client = ThrowingEpisodeAdAnalysisClient(error: EpisodeAdAnalysisHTTPError(
            statusCode: 429,
            code: "daily_input_token_cap_exceeded",
            detail: nil
        ))
        let store = EpisodeAdAnalysisStore(
            client: client,
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        )
        let transcript = makeTranscriptDocument(episodeID: "ad-cap-kind")

        store.startAnalysis(transcript: transcript, modelContext: context)

        #expect(await waitUntil {
            store.record(for: transcript.episodeID)?.state == .failed
        })
        let record = try #require(store.record(for: transcript.episodeID))
        #expect(record.failureKind == .capExceeded)
        guard case .failed(let failedRecord, _) = store.jobState(for: transcript) else {
            Issue.record("expected a failed job state")
            return
        }
        #expect(failedRecord.failureKind == .capExceeded)
    }

    @Test("Non-cap failures thread their failure kind")
    func nonCapFailuresThreadTheirFailureKind() async throws {
        // A 5xx submit can follow a started run, so it is not repeated.
        let cases: [(error: Error, kind: EpisodeAnalysisFailureKind, submits: Int)] = [
            (EpisodeAdAnalysisHTTPError(statusCode: 500, code: "internal", detail: nil), .serviceUnavailable, 1),
            (EpisodeAdAnalysisHTTPError(statusCode: 429, code: "rate_limited_other", detail: nil), .generic, 1)
        ]
        for (index, testCase) in cases.enumerated() {
            let container = try OpenCastModelContainerFactory.make(inMemory: true)
            let context = ModelContext(container)
            let temporaryDirectory = try makeTemporaryDirectory()
            let client = ThrowingEpisodeAdAnalysisClient(error: testCase.error)
            let store = EpisodeAdAnalysisStore(
                client: client,
                fileStore: EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory),
                pollingSleep: { _ in }
            )
            let transcript = makeTranscriptDocument(episodeID: "ad-generic-kind-\(index)")

            store.startAnalysis(transcript: transcript, modelContext: context)

            #expect(await waitUntil {
                store.record(for: transcript.episodeID)?.state == .failed
            })
            let record = try #require(store.record(for: transcript.episodeID))
            #expect(record.failureKind == testCase.kind)
            #expect(client.calls == testCase.submits)
        }
    }

    @Test("A response containing an unknown span kind fails cleanly, never a trusted skip")
    func unknownSpanKindFailsCleanlyInsteadOfTrustedSkip() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let client = FakeEpisodeAdAnalysisClient()
        client.spanKind = .unknown
        let store = EpisodeAdAnalysisStore(
            client: client,
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        )
        let transcript = makeTranscriptDocument(episodeID: "ad-unknown-kind")

        store.startAnalysis(transcript: transcript, modelContext: context)

        #expect(await waitUntil {
            store.record(for: transcript.episodeID)?.state == .failed
        })
        let record = try #require(store.record(for: transcript.episodeID))
        #expect(record.failureKind == .generic)
        #expect(record.errorMessage == EpisodeAdAnalysisError.unrecognizedSpanKind.localizedDescription)
        #expect(store.document(for: transcript.episodeID) == nil)
    }

    @Test("A successful rerun clears the stored failure kind")
    func successfulRerunClearsFailureKind() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let client = ThrowingEpisodeAdAnalysisClient(error: EpisodeAdAnalysisHTTPError(
            statusCode: 429,
            code: "daily_request_cap_exceeded",
            detail: nil
        ))
        let store = EpisodeAdAnalysisStore(
            client: client,
            fileStore: EpisodeAdAnalysisFileStore(baseDirectory: temporaryDirectory)
        )
        let transcript = makeTranscriptDocument(episodeID: "ad-cap-clears")

        store.startAnalysis(transcript: transcript, modelContext: context)
        #expect(await waitUntil {
            store.record(for: transcript.episodeID)?.state == .failed
        })

        client.error = nil
        store.startAnalysis(transcript: transcript, modelContext: context)
        #expect(await waitUntil {
            store.record(for: transcript.episodeID)?.state == .completed
        })
        let record = try #require(store.record(for: transcript.episodeID))
        #expect(record.failureKind == nil)
    }

    #if DEBUG
    #endif

    @Test("Ad-analysis request carries the feed's declared runtime only when known")
    func adAnalysisRequestCarriesDeclaredDurationOnlyWhenKnown() throws {
        var request = makeAPIRequest(requestID: "client-declared")
        let encoder = JSONEncoder.openCastAdAnalysisTestEncoder
        #expect(String(decoding: try encoder.encode(request), as: UTF8.self).contains("declared_duration") == false)
        request.transcript.declaredDuration = 2471
        let payload = String(decoding: try encoder.encode(request), as: UTF8.self)
        #expect(payload.contains(#""audio_duration":30,"declared_duration":2471,"fingerprint":"fingerprint""#))
    }

    private func makeAPIRequest(requestID: String) -> EpisodeAdAnalysisAPIRequest {
        EpisodeAdAnalysisAPIRequest(
            schemaVersion: 1,
            requestID: requestID,
            episodeID: "client-episode",
            podcastID: "https://example.com/feed.xml",
            episodeTitle: "Client Episode",
            podcastTitle: "Client Podcast",
            transcript: EpisodeAdAnalysisAPITranscriptMetadata(
                languageCode: "en",
                audioDuration: 30,
                modelIdentifier: "model",
                modelVersion: "v1",
                modelTreeSHA256: "tree-sha",
                fingerprint: "fingerprint",
                updatedAt: Date(timeIntervalSince1970: 1_780_000_000),
                state: "completed",
                segmentCount: 2
            ),
            segments: [
                EpisodeAdAnalysisAPISegment(
                    id: 4,
                    start: 10.5,
                    end: 14,
                    text: "This part is brought to you by Example Sponsor."
                ),
                EpisodeAdAnalysisAPISegment(
                    id: 6,
                    start: 14,
                    end: 21.25,
                    text: "Visit the sponsor for more details."
                )
            ]
        )
    }

    private func encodedJSONString(_ request: EpisodeAdAnalysisAPIRequest) throws -> String {
        let data = try JSONEncoder.openCastAdAnalysisTestEncoder.encode(request)
        return String(decoding: data, as: UTF8.self)
    }

    private func writeTranscript(
        _ document: EpisodeTranscriptDocument,
        fileStore: EpisodeTranscriptFileStore,
        modelContext: ModelContext,
        state: EpisodeTranscriptState = .completed
    ) throws -> String {
        let fingerprint = fileStore.fingerprint(
            sourceFileSHA256: document.sourceFileSHA256,
            modelIdentifier: document.modelIdentifier,
            modelVersion: document.modelVersion,
            modelTreeSHA256: document.modelTreeSHA256
        )
        let relativePath = fileStore.relativePath(episodeID: document.episodeID, fingerprint: fingerprint)
        try fileStore.write(document, relativePath: relativePath)
        modelContext.insert(EpisodeTranscriptRecord(
            episodeID: document.episodeID,
            podcastID: document.podcastID,
            sourceAudioURL: document.sourceAudioURL,
            sourceFileByteCount: document.sourceFileByteCount,
            sourceFileSHA256: document.sourceFileSHA256,
            modelIdentifier: document.modelIdentifier,
            modelVersion: document.modelVersion,
            modelTreeSHA256: document.modelTreeSHA256,
            languageCode: document.languageCode,
            state: state,
            audioDuration: document.audioDuration,
            completedDuration: document.audioDuration,
            checkpointCount: document.checkpoints.count,
            transcriptRelativePath: relativePath,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt
        ))
        try modelContext.save()
        return relativePath
    }

    private func makeTranscriptDocument(
        episodeID: String,
        podcastID: String = "https://example.com/feed.xml",
        updatedAt: Date = Date(timeIntervalSince1970: 1_780_000_000),
        sponsorSegmentText: String = "This episode is brought to you by Example Sponsor.",
        extraSegmentText: String? = nil
    ) -> EpisodeTranscriptDocument {
        var segments = [
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
                text: sponsorSegmentText,
                avgLogProbability: -0.1,
                noSpeechProbability: 0.01
            )
        ]
        if let extraSegmentText {
            segments.append(OpenCastTranscriptSegment(
                id: 2,
                start: 12,
                end: 16,
                text: extraSegmentText,
                avgLogProbability: -0.1,
                noSpeechProbability: 0.01
            ))
        }

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

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "OpenCastAdAnalysisTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func startAndWait(
        store: EpisodeAdAnalysisStore,
        transcript: EpisodeTranscriptDocument,
        modelContext: ModelContext
    ) async {
        store.startAnalysis(transcript: transcript, modelContext: modelContext)
        #expect(await waitUntil {
            !store.hasActiveJob
                && store.record(for: transcript.episodeID)?.state == .completed
        })
    }
}


private final class ThrowingEpisodeAdAnalysisClient: EpisodeAdAnalysisClient, @unchecked Sendable {
    var error: Error?
    var revision: String?
    var calls = 0
    var lastRetryFailed: Bool?

    func servingPolicyRevision() async throws -> String? { revision }

    init(error: Error?) {
        self.error = error
    }

    func analyze(_ request: EpisodeAdAnalysisAPIRequest) async throws -> EpisodeAdAnalysisSubmitOutcome {
        calls += 1
        lastRetryFailed = request.retryFailed
        if let error {
            throw error
        }

        return .completed(EpisodeAdAnalysisAPIResponse(
            schemaVersion: 1,
            requestID: request.requestID,
            model: "gemini-3.5-flash",
            policy: EpisodeAdAnalysisContract.expectedPolicy,
            spans: [],
            warnings: [],
            usage: nil
        ))
    }

    func pollJob(id: String) async throws -> EpisodeAdAnalysisJobPollOutcome {
        throw EpisodeAdAnalysisError.clientDisabled
    }
}

private final class FakeEpisodeAdAnalysisClient: EpisodeAdAnalysisClient, @unchecked Sendable {
    var lastRequest: EpisodeAdAnalysisAPIRequest?
    var spanKind: EpisodeAdAnalysisSpanKind = .hostReadAd

    func analyze(_ request: EpisodeAdAnalysisAPIRequest) async throws -> EpisodeAdAnalysisSubmitOutcome {
        lastRequest = request
        return .completed(EpisodeAdAnalysisAPIResponse(
            schemaVersion: 1,
            requestID: request.requestID,
            model: "gemini-3.5-flash",
            policy: EpisodeAdAnalysisContract.expectedPolicy,
            spans: [
                EpisodeAdAnalysisAPIAdSpan(
                    kind: spanKind,
                    label: "Example Sponsor",
                    startSegmentID: 1,
                    endSegmentID: 1,
                    startTime: 5,
                    endTime: 12,
                    confidence: 0.96,
                    evidenceQuote: "brought to you"
                )
            ],
            warnings: [],
            usage: EpisodeAdAnalysisAPIUsage(
                promptTokenCount: 100,
                candidatesTokenCount: 20,
                totalTokenCount: 120
            )
        ))
    }

    func pollJob(id: String) async throws -> EpisodeAdAnalysisJobPollOutcome {
        throw EpisodeAdAnalysisError.clientDisabled
    }
}

private actor HangingEpisodeAdAnalysisClient: EpisodeAdAnalysisClient {
    private(set) var requestCount = 0
    private var shouldRelease = false

    func analyze(_ request: EpisodeAdAnalysisAPIRequest) async throws -> EpisodeAdAnalysisSubmitOutcome {
        requestCount += 1
        while !shouldRelease {
            try await Task.sleep(for: .milliseconds(10))
            try Task.checkCancellation()
        }
        return .completed(EpisodeAdAnalysisAPIResponse(
            schemaVersion: request.schemaVersion,
            requestID: request.requestID,
            model: "gemini-3.5-flash",
            policy: EpisodeAdAnalysisContract.expectedPolicy,
            spans: [
                EpisodeAdAnalysisAPIAdSpan(
                    kind: .hostReadAd,
                    label: "Example Sponsor",
                    startSegmentID: 1,
                    endSegmentID: 1,
                    startTime: 5,
                    endTime: 12,
                    confidence: 0.96,
                    evidenceQuote: "brought to you"
                )
            ],
            warnings: [],
            usage: nil
        ))
    }

    func pollJob(id: String) async throws -> EpisodeAdAnalysisJobPollOutcome {
        throw EpisodeAdAnalysisError.clientDisabled
    }

    func waitForRequest() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(60)
        while ContinuousClock.now < deadline {
            if requestCount > 0 {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return requestCount > 0
    }

    func currentRequestCount() -> Int {
        requestCount
    }

    func release() {
        shouldRelease = true
    }
}

private extension JSONEncoder {
    static var openCastAdAnalysisTestEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
