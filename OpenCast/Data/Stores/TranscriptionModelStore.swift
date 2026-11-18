import Foundation
import Observation
import OpenCastTranscription
import SwiftData

/// The two Whisper models. Fast (tiny.en) ships inside the app and is the one
/// every automatic Whisper run uses, so `state` is always about it and never
/// needs a download. Accurate (large-v3) is an optional download, managed in
/// Settings through `accurateState`, and runs only when the Whisper engine is
/// explicitly set to the selected model.
@Observable
final class TranscriptionModelStore {
    static let modelChoicePreferenceKey = "transcription.model.choice"
    /// The bundled model automatic Whisper runs use.
    static let fastModel = OpenCastWhisperModel.tinyEnglish
    /// The downloadable model.
    static let accurateModel = OpenCastWhisperModel.largeV3

    @ObservationIgnored private let stateChanges = StoreChangeNotifier()

    private(set) var selectedChoice: TranscriptionModelChoice = .defaultChoice

    /// The Fast model's state: installed unless the app bundle is damaged.
    private(set) var state: TranscriptionModelState = .unknown {
        didSet {
            guard oldValue != state else {
                return
            }
            stateChanges.notify()
        }
    }

    /// The Accurate model's download state.
    private(set) var accurateState: TranscriptionModelState = .unknown {
        didSet {
            guard oldValue != accurateState else {
                return
            }
            stateChanges.notify()
        }
    }

    @ObservationIgnored private let installer: any TranscriptionModelInstalling
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var activeInstallOperationID: UUID?

    init(
        installer: any TranscriptionModelInstalling = RemoteTranscriptionModelInstaller()
    ) {
        self.installer = installer
    }

    /// The selected model's summary when it is installed.
    var installedSummary: OpenCastWhisperModelInstalledSummary? {
        switch selectedChoice {
        case .fastTinyEnglish:
            Self.summary(of: state)
        case .accurateLargeV3:
            Self.summary(of: accurateState)
        }
    }

    /// The Fast model's summary, read from its receipt rather than the last
    /// published `state`, so callers can resolve before the store has loaded.
    func installedModelSummary() throws -> OpenCastWhisperModelInstalledSummary {
        try installer.installedSummary(model: Self.fastModel, version: Self.fastModel.defaultRemoteVersion)
    }

    /// Whether an Accurate operation is running.
    var isBusy: Bool {
        switch accurateState {
        case .checking, .installing, .deleting:
            true
        case .unknown, .notInstalled, .installed, .repairAvailable, .failed:
            false
        }
    }

    // Test seam — no production callers (dead-code audit Low 40).
    var canStartTranscription: Bool {
        if case .installed = state {
            true
        } else {
            false
        }
    }

    var changeSequence: Int {
        stateChanges.sequence
    }

    func waitForChange(after sequence: Int) async throws {
        try await stateChanges.wait(after: sequence)
    }

    // Test seam — no production callers (dead-code audit Low 40).
    func loadLocalStatus() {
        state = fastStatus()
        accurateState = accurateLocalStatus()
    }

    func load(modelContext: ModelContext) {
        selectedChoice = storedChoice(modelContext: modelContext)
        state = fastStatus()
        accurateState = accurateLocalStatus()
    }

    @discardableResult
    func setSelectedChoice(
        _ choice: TranscriptionModelChoice,
        modelContext: ModelContext
    ) -> Bool {
        let previousChoice = selectedChoice
        selectedChoice = choice
        do {
            try LocalPreferenceRecord.upsert(
                key: Self.modelChoicePreferenceKey,
                value: choice.rawValue,
                modelContext: modelContext
            )
            try modelContext.save()
            return true
        } catch {
            selectedChoice = previousChoice
            accurateState = .failed("Unable to update transcript model: \(error.localizedDescription)")
            return false
        }
    }

    /// The pipeline's install step. The Fast model ships with the app, so
    /// there is nothing to download: this reads the bundled copy again and
    /// always signals a change, so a caller waiting on one never hangs.
    @discardableResult
    func installPinnedModel() -> Bool {
        state = fastStatus()
        stateChanges.notify()
        return true
    }

    /// Records a transcription-start failure against the Fast model, as the
    /// pipeline reports it; `installPinnedModel` reads the bundle again.
    func fail(_ message: String) {
        state = .failed(message)
    }

    // MARK: Accurate

    @discardableResult
    func installAccurateModel() -> Bool {
        startAccurateInstall()
    }

    @discardableResult
    func repairAccurateModel() -> Bool {
        startAccurateInstall()
    }

    func cancelAccurateInstall() {
        operationTask?.cancel()
    }

    func failAccurate(_ message: String) {
        accurateState = .failed(message)
    }

    func checkAccurateModel() {
        guard operationTask == nil else {
            return
        }

        operationTask = Task { [self] in
            accurateState = .checking
            do {
                let manifest = try await installer.fetchManifest()
                try Task.checkCancellation()
                accurateState = try checkedAccurateState(manifest: manifest)
            } catch is CancellationError {
                accurateState = accurateLocalStatus()
            } catch {
                accurateState = .failed(error.localizedDescription)
            }
            operationTask = nil
        }
    }

    func accurateModelRemoteByteCount() async throws -> Int64 {
        let manifest = try await installer.fetchManifest()
        return try accurateRemoteModel(in: manifest).totalByteCount
    }

    func deleteAccurateModel() {
        guard operationTask == nil else {
            return
        }

        operationTask = Task {
            try? performDeleteAccurateModel()
            operationTask = nil
        }
    }

    /// Deletes the downloaded Accurate model; the bundled Fast model stays.
    func deleteInstalledModelImmediately() throws {
        operationTask?.cancel()
        operationTask = nil
        activeInstallOperationID = nil
        try performDeleteAccurateModel()
        accurateState = accurateLocalStatus()
    }

    /// Deliberately synchronous and main-actor: the data-nuke ordering
    /// guarantee beside `resetRuntimeStateAfterDataNuke` depends on the
    /// removal completing before the nuke proceeds. The catch keeps any
    /// throw from stranding `.deleting` — the Settings section renders that
    /// state as a bare spinner with no way out.
    private func performDeleteAccurateModel() throws {
        accurateState = .deleting
        do {
            try installer.deleteInstalledModel(
                model: Self.accurateModel,
                version: Self.accurateModel.defaultRemoteVersion
            )
            accurateState = accurateLocalStatus()
        } catch {
            accurateState = .failed(error.localizedDescription)
            throw error
        }
    }

    func resetAfterDataNuke() {
        operationTask?.cancel()
        operationTask = nil
        activeInstallOperationID = nil
        selectedChoice = .defaultChoice
        state = fastStatus()
        accurateState = accurateLocalStatus()
    }

    private func startAccurateInstall() -> Bool {
        guard operationTask == nil else {
            return false
        }

        let operationID = UUID()
        let model = Self.accurateModel
        let version = model.defaultRemoteVersion
        activeInstallOperationID = operationID
        // Keep the store alive for this finite operation, then clear the task
        // below. The installer's escaping progress callback must stay weak.
        operationTask = Task { [self] in
            accurateState = .checking
            do {
                let manifest = try await installer.fetchManifest()
                let remoteModel = try accurateRemoteModel(in: manifest)
                accurateState = .installing(OpenCastWhisperModelInstallProgress(
                    modelIdentifier: remoteModel.modelID,
                    version: remoteModel.version,
                    completedFileCount: 0,
                    totalFileCount: remoteModel.files.count,
                    completedByteCount: 0,
                    totalByteCount: remoteModel.totalByteCount,
                    currentFilePath: nil
                ))
                let summary = try await installer.install(
                    manifest: manifest,
                    model: model,
                    version: version,
                    progress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.applyInstallProgress(progress, operationID: operationID)
                        }
                    }
                )
                try Task.checkCancellation()
                activeInstallOperationID = nil
                accurateState = .installed(summary)
            } catch is CancellationError {
                activeInstallOperationID = nil
                accurateState = accurateLocalStatus()
            } catch {
                activeInstallOperationID = nil
                accurateState = .failed(error.localizedDescription)
            }
            operationTask = nil
        }
        return true
    }

    private func applyInstallProgress(
        _ progress: OpenCastWhisperModelInstallProgress,
        operationID: UUID
    ) {
        guard activeInstallOperationID == operationID,
              case .installing(let currentProgress) = accurateState,
              currentProgress.modelIdentifier == progress.modelIdentifier,
              currentProgress.version == progress.version
        else {
            return
        }

        accurateState = .installing(progress)
    }

    private func checkedAccurateState(manifest: RemoteWhisperModelManifest) throws -> TranscriptionModelState {
        let remoteModel = try accurateRemoteModel(in: manifest)
        do {
            let summary = try installer.installedSummary(
                model: Self.accurateModel,
                version: Self.accurateModel.defaultRemoteVersion
            )
            if summary.treeSHA256.lowercased() == remoteModel.treeSHA256.lowercased() {
                return .installed(summary)
            }
            return .repairAvailable(summary)
        } catch let error as OpenCastTranscriptionError {
            guard case .modelNotInstalled = error else {
                throw error
            }
            return .notInstalled
        }
    }

    private func fastStatus() -> TranscriptionModelState {
        localStatus(model: Self.fastModel)
    }

    private func accurateLocalStatus() -> TranscriptionModelState {
        localStatus(model: Self.accurateModel)
    }

    private func localStatus(model: OpenCastWhisperModel) -> TranscriptionModelState {
        do {
            return .installed(try installer.installedSummary(model: model, version: model.defaultRemoteVersion))
        } catch let error as OpenCastTranscriptionError {
            guard case .modelNotInstalled = error else {
                return .failed(error.localizedDescription)
            }
            return .notInstalled
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func storedChoice(modelContext: ModelContext) -> TranscriptionModelChoice {
        guard let rawValue = try? LocalPreferenceRecord.preference(
            forKey: Self.modelChoicePreferenceKey,
            modelContext: modelContext
        )?.value else {
            return .defaultChoice
        }
        return TranscriptionModelChoice(rawValue: rawValue) ?? .defaultChoice
    }

    private static func summary(of state: TranscriptionModelState) -> OpenCastWhisperModelInstalledSummary? {
        switch state {
        case .installed(let summary), .repairAvailable(let summary):
            summary
        default:
            nil
        }
    }

    private func accurateRemoteModel(in manifest: RemoteWhisperModelManifest) throws -> RemoteWhisperModel {
        let model = Self.accurateModel
        let version = model.defaultRemoteVersion
        guard let remoteModel = manifest.model(modelIdentifier: model.rawValue, version: version) else {
            throw OpenCastTranscriptionError.remoteManifestMissingModel(
                modelIdentifier: model.rawValue,
                version: version
            )
        }
        return remoteModel
    }
}
