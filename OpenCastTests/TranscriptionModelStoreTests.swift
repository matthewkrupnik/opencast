import Foundation
import OpenCastTranscription
import SwiftData
import Testing
@testable import OpenCast

@MainActor
@Suite("Transcription model store")
struct TranscriptionModelStoreTests {
    @Test("A missing Accurate model loads as not installed while the bundled Fast model is installed")
    func missingModelLoadsAsNotInstalled() throws {
        let store = TranscriptionModelStore(installer: FakeTranscriptionModelInstaller(isInstalled: false))

        store.loadLocalStatus()

        #expect(store.accurateState == .notInstalled)
        #expect(store.state == .installed(FakeTranscriptionModelInstaller.fastSummary))
        #expect(try store.installedModelSummary() == FakeTranscriptionModelInstaller.fastSummary)
    }

    @Test("Fast is the default choice; the choice persists and picks the summary the selected engine runs")
    func choiceDefaultsToFastPersistsAndPicksTheSummary() throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let installer = FakeTranscriptionModelInstaller(isInstalled: false)
        let store = TranscriptionModelStore(installer: installer)
        store.load(modelContext: context)

        #expect(store.selectedChoice == .fastTinyEnglish)
        #expect(store.installedSummary == FakeTranscriptionModelInstaller.fastSummary)

        #expect(store.setSelectedChoice(.accurateLargeV3, modelContext: context))
        // Accurate isn't downloaded, so the selected engine has nothing to run.
        #expect(store.installedSummary == nil)

        installer.isInstalled = true
        let reloaded = TranscriptionModelStore(installer: installer)
        reloaded.load(modelContext: context)
        #expect(reloaded.selectedChoice == .accurateLargeV3)
        #expect(reloaded.installedSummary == installer.summary)
        // Automatic runs stay on Fast whatever is picked.
        #expect(try reloaded.installedModelSummary() == FakeTranscriptionModelInstaller.fastSummary)

        reloaded.resetAfterDataNuke()
        #expect(reloaded.selectedChoice == .fastTinyEnglish)
    }

    @Test("The pipeline's install step re-reads the bundled model, downloads nothing and always signals")
    func pipelineInstallRereadsTheBundledModel() async throws {
        let installer = FakeTranscriptionModelInstaller(isInstalled: false)
        let store = TranscriptionModelStore(installer: installer)
        store.loadLocalStatus()
        store.fail("Transcription couldn't start.")
        #expect(store.state == .failed("Transcription couldn't start."))

        let sequence = store.changeSequence
        #expect(store.installPinnedModel())
        #expect(store.state == .installed(FakeTranscriptionModelInstaller.fastSummary))
        #expect(installer.installRequestCount == 0)

        // Even with nothing to change, a waiter is released.
        let unchanged = store.changeSequence
        #expect(unchanged > sequence)
        #expect(store.installPinnedModel())
        try await store.waitForChange(after: unchanged)
        #expect(store.accurateState == .notInstalled)
    }

    @Test("Active transcription blocks model install with message")
    func activeTranscriptionBlocksModelInstallWithMessage() async throws {
        let container = try OpenCastModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let temporaryDirectory = try makeTemporaryDirectory()
        let audioURL = try writeAudioPlaceholder(in: temporaryDirectory, contents: "active model choice audio")
        let installer = FakeTranscriptionModelInstaller(isInstalled: true)
        let transcriptionModels = TranscriptionModelStore(installer: installer)
        let blockingTranscriber = BlockingModelChoiceEpisodeTranscriber()
        let transcriptions = EpisodeTranscriptionStore(
            transcriber: blockingTranscriber,
            fileStore: EpisodeTranscriptFileStore(baseDirectory: temporaryDirectory)
        )
        let appModel = OpenCastAppModel(
            transcriptionModels: transcriptionModels,
            transcriptions: transcriptions,
            allowsAutomaticFeedRefresh: false
        )
        transcriptionModels.load(modelContext: context)
        let episode = makeEpisode(episodeID: "active-model-choice")
        let record = completedDownloadRecord(episode: episode)

        transcriptions.startTranscription(
            episode,
            downloadRecord: record,
            localFileURL: audioURL,
            modelSummary: installer.summary,
            modelContext: context
        )

        #expect(await waitUntil { blockingTranscriber.requestCount == 1 })
        #expect(!appModel.installTranscriptionModel())
        #expect(installer.requestedInstallModel == nil)
        if case .failed(let message) = transcriptionModels.accurateState {
            #expect(message == "Finish or cancel the active transcript before installing the speech model.")
        } else {
            Issue.record("Expected failed model-install state, got \(transcriptionModels.accurateState).")
        }

        await transcriptions.unloadRuntime()
    }

    @Test("Install progress updates state and finishes installed")
    func installProgressUpdatesStateAndFinishesInstalled() async {
        let installer = FakeTranscriptionModelInstaller(isInstalled: false)
        let store = TranscriptionModelStore(installer: installer)

        #expect(store.installAccurateModel())

        #expect(await waitUntil {
            if case .installing(let progress) = store.accurateState {
                progress.totalByteCount == 10
            } else {
                false
            }
        })
        #expect(await waitUntil {
            if case .installed(let summary) = store.accurateState {
                summary.treeSHA256 == installer.summary.treeSHA256
            } else {
                false
            }
        })
    }

    @Test("Cancelling install clears ownership and ignores late progress before retry")
    func cancelledInstallCanRetry() async {
        let installer = FakeTranscriptionModelInstaller(isInstalled: false)
        installer.installDelay = .seconds(60)
        let store = TranscriptionModelStore(installer: installer)
        #expect(store.installAccurateModel())
        #expect(await waitUntil { installer.installRequestCount == 1 })
        store.cancelAccurateInstall()
        #expect(await waitUntil { store.accurateState == .notInstalled })
        #expect(installer.emitLateProgress())
        #expect(await waitUntil { installer.lateProgressDeliveryAcknowledged })
        #expect(store.accurateState == .notInstalled)

        installer.installDelay = .milliseconds(40)
        #expect(store.installAccurateModel())
        #expect(await waitUntil { installer.isInstalled })
        #expect(installer.installRequestCount == 2)
    }

    @Test("A finite install owns its store until completion then releases it")
    func installOwnsStoreUntilCompletion() async {
        let installer = FakeTranscriptionModelInstaller(isInstalled: false)
        var store: TranscriptionModelStore? = TranscriptionModelStore(installer: installer)
        weak let releasedStore = store
        #expect(store?.installAccurateModel() == true)
        store = nil
        #expect(releasedStore != nil)
        #expect(await waitUntil { releasedStore == nil })
        #expect(installer.isInstalled)
        #expect(installer.emitLateProgress())
    }

    @Test("Starting install reports false while another model operation is active")
    func startingInstallReportsFalseWhileAnotherModelOperationIsActive() async {
        let installer = FakeTranscriptionModelInstaller(isInstalled: false)
        let store = TranscriptionModelStore(installer: installer)

        #expect(store.installAccurateModel())
        #expect(!store.installAccurateModel())

        #expect(await waitUntil {
            if case .installed = store.accurateState {
                true
            } else {
                false
            }
        })
        #expect(installer.installRequestCount == 1)
    }

    @Test("Installing Accurate uses the pinned large-v3 release")
    func installingUsesPinnedLargeV3Release() async {
        let installer = FakeTranscriptionModelInstaller(isInstalled: false)
        let store = TranscriptionModelStore(installer: installer)

        #expect(store.installAccurateModel())

        #expect(await waitUntil {
            if case .installed(let installedSummary) = store.accurateState {
                installedSummary.modelIdentifier == OpenCastWhisperModel.largeV3.rawValue
            } else {
                false
            }
        })
        #expect(installer.requestedInstallModel == .largeV3)
        #expect(installer.requestedInstallVersion == OpenCastWhisperModel.largeV3.defaultRemoteVersion)
    }

    @Test("Late install progress cannot overwrite installed state")
    func lateInstallProgressCannotOverwriteInstalledState() async {
        let installer = FakeTranscriptionModelInstaller(isInstalled: false)
        let store = TranscriptionModelStore(installer: installer)

        #expect(store.installAccurateModel())

        #expect(await waitUntil {
            if case .installed = store.accurateState {
                true
            } else {
                false
            }
        })
        #expect(installer.emitLateProgress())
        #expect(await waitUntil { installer.lateProgressDeliveryAcknowledged })
        if case .installed(let summary) = store.accurateState {
            #expect(summary.treeSHA256 == installer.summary.treeSHA256)
        } else {
            Issue.record("Expected installed state after late progress, got \(store.accurateState)")
        }
    }

    @Test("Manifest mismatch reports repair")
    func manifestMismatchReportsRepair() async {
        let installed = OpenCastWhisperModelInstalledSummary(
            modelIdentifier: OpenCastWhisperModel.largeV3.rawValue,
            version: OpenCastWhisperModel.largeV3.defaultRemoteVersion,
            totalByteCount: 10,
            treeSHA256: String(repeating: "1", count: 64)
        )
        let remote = OpenCastWhisperModelInstalledSummary(
            modelIdentifier: installed.modelIdentifier,
            version: installed.version,
            totalByteCount: installed.totalByteCount,
            treeSHA256: String(repeating: "2", count: 64)
        )
        let store = TranscriptionModelStore(installer: FakeTranscriptionModelInstaller(
            isInstalled: true,
            summary: installed,
            manifestSummary: remote
        ))

        store.checkAccurateModel()

        #expect(await waitUntil {
            if case .repairAvailable(let summary) = store.accurateState {
                summary.treeSHA256 == installed.treeSHA256
            } else {
                false
            }
        })
    }

    @Test("A throwing delete leaves failed, not a stranded deleting spinner")
    func throwingDeleteLeavesFailedState() async {
        let installer = FakeTranscriptionModelInstaller(isInstalled: true)
        installer.deleteError = CocoaError(.fileWriteNoPermission)
        let store = TranscriptionModelStore(installer: installer)
        store.loadLocalStatus()

        store.deleteAccurateModel()

        #expect(await waitUntil {
            if case .failed = store.accurateState {
                true
            } else {
                false
            }
        })
    }

    @Test("A throwing immediate delete rethrows and leaves failed, not deleting")
    func throwingImmediateDeleteRethrowsAndLeavesFailedState() {
        let installer = FakeTranscriptionModelInstaller(isInstalled: true)
        installer.deleteError = CocoaError(.fileWriteNoPermission)
        let store = TranscriptionModelStore(installer: installer)
        store.loadLocalStatus()

        #expect(throws: CocoaError.self) {
            try store.deleteInstalledModelImmediately()
        }
        guard case .failed = store.accurateState else {
            Issue.record("Expected failed state, got \(store.accurateState)")
            return
        }
    }

    private func makeEpisode(episodeID: String) -> EpisodeListItemSnapshot {
        .fixture(
            episodeID: episodeID,
            audioURL: "https://example.com/\(episodeID).mp3",
            guid: episodeID
        )
    }

    private func completedDownloadRecord(episode: EpisodeListItemSnapshot) -> EpisodeDownloadRecord {
        EpisodeDownloadRecord(
            episodeID: episode.episodeID,
            podcastID: episode.podcastID,
            sourceAudioURL: episode.audioURL ?? "",
            localRelativePath: "EpisodeDownloads/\(episode.episodeID).mp3",
            state: .completed,
            bytesReceived: 10,
            bytesExpected: 10
        )
    }

    private func writeAudioPlaceholder(in directory: URL, contents: String) throws -> URL {
        let url = directory.appending(path: UUID().uuidString).appendingPathExtension("mp3")
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "OpenCastTranscriptionModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class FakeTranscriptionModelInstaller: TranscriptionModelInstalling, @unchecked Sendable {
    var isInstalled: Bool
    var deleteError: Error?
    let summary: OpenCastWhisperModelInstalledSummary
    let manifestSummary: OpenCastWhisperModelInstalledSummary
    var installRequestCount = 0
    var installDelay: Duration = .milliseconds(40)
    var requestedInstallModel: OpenCastWhisperModel?
    var requestedInstallVersion: String?
    private(set) var lateProgressDeliveryAcknowledged = false
    private var installProgress: OpenCastWhisperModelInstallProgressHandler?

    init(
        isInstalled: Bool,
        summary: OpenCastWhisperModelInstalledSummary = OpenCastWhisperModelInstalledSummary(
            modelIdentifier: OpenCastWhisperModel.largeV3.rawValue,
            version: OpenCastWhisperModel.largeV3.defaultRemoteVersion,
            totalByteCount: 10,
            treeSHA256: String(repeating: "a", count: 64)
        ),
        manifestSummary: OpenCastWhisperModelInstalledSummary? = nil
    ) {
        self.isInstalled = isInstalled
        self.summary = summary
        self.manifestSummary = manifestSummary ?? summary
    }

    static let fastSummary = OpenCastWhisperModelInstalledSummary(
        modelIdentifier: OpenCastWhisperModel.tinyEnglish.rawValue,
        version: OpenCastWhisperModel.tinyEnglish.defaultRemoteVersion,
        totalByteCount: 49_616_040,
        treeSHA256: String(repeating: "f", count: 64)
    )

    func installedSummary(model: OpenCastWhisperModel, version: String) throws -> OpenCastWhisperModelInstalledSummary {
        // The bundled model is always there, as the real install store reads it.
        if model.isBundled {
            return Self.fastSummary
        }
        guard isInstalled,
              summary.modelIdentifier == model.rawValue,
              summary.version == version else {
            throw OpenCastTranscriptionError.modelNotInstalled(
                modelIdentifier: model.rawValue,
                version: version
            )
        }
        return summary
    }

    func fetchManifest() async throws -> RemoteWhisperModelManifest {
        RemoteWhisperModelManifest(
            schemaVersion: 1,
            generatedAt: "2026-06-29T00:00:00Z",
            models: [remoteModel(summary: manifestSummary)]
        )
    }

    func install(
        manifest: RemoteWhisperModelManifest,
        model: OpenCastWhisperModel,
        version: String,
        progress: OpenCastWhisperModelInstallProgressHandler?
    ) async throws -> OpenCastWhisperModelInstalledSummary {
        installRequestCount += 1
        requestedInstallModel = model
        requestedInstallVersion = version
        installProgress = progress
        progress?(OpenCastWhisperModelInstallProgress(
            modelIdentifier: summary.modelIdentifier,
            version: summary.version,
            completedFileCount: 1,
            totalFileCount: 2,
            completedByteCount: 5,
            totalByteCount: 10,
            currentFilePath: "model/config.json"
        ))
        try await Task.sleep(for: installDelay)
        isInstalled = true
        return summary
    }

    func emitLateProgress() -> Bool {
        guard let installProgress else {
            return false
        }

        installProgress(OpenCastWhisperModelInstallProgress(
            modelIdentifier: summary.modelIdentifier,
            version: summary.version,
            completedFileCount: 1,
            totalFileCount: 2,
            completedByteCount: 6,
            totalByteCount: 10,
            currentFilePath: "model/late.bin"
        ))
        Task { @MainActor [weak self] in
            self?.lateProgressDeliveryAcknowledged = true
        }
        return true
    }

    func deleteInstalledModel(model: OpenCastWhisperModel, version: String) throws {
        if let deleteError {
            throw deleteError
        }
        isInstalled = false
    }

    private func remoteModel(summary: OpenCastWhisperModelInstalledSummary) -> RemoteWhisperModel {
        RemoteWhisperModel(
            modelID: summary.modelIdentifier,
            version: summary.version,
            modelFolder: "model",
            tokenizerFolder: "tokenizer",
            totalByteCount: summary.totalByteCount,
            treeSHA256: summary.treeSHA256,
            files: []
        )
    }
}

private final class BlockingModelChoiceEpisodeTranscriber: EpisodeTranscribing, @unchecked Sendable {
    var requestCount = 0

    func transcribe(
        _ request: EpisodeTranscriptionRunRequest
    ) -> AsyncThrowingStream<EpisodeTranscriptionRunEvent, Error> {
        requestCount += 1
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.progress(EpisodeTranscriptionProgress(
                    audioDuration: 60,
                    completedDuration: 0,
                    checkpointCount: 0,
                    currentWindowIndex: 0,
                    currentText: nil
                )))
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func unload() async {
    }
}
