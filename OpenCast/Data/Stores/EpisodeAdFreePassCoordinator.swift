import Foundation
import Observation
import OpenCastTranscription
import SwiftData

@Observable
final class EpisodeAdFreePassCoordinator {
    private enum FailureMessage {
        static let transcriptFailed = "Transcript failed."
        static let transcriptCancelled = "Transcript cancelled."
        static let transcriptUnavailable = "Transcript unavailable."
        static let analysisFailed = "Promo/ad analysis failed."
    }

    private(set) var queueState: AdFreePassQueueState = .idle
    private(set) var activeItem: AdFreePassQueueItem?
    private(set) var currentStage: EpisodeAdFreePassStage?
    private(set) var drainCompletedCount = 0
    private(set) var drainFailedCount = 0
    private(set) var drainOutcomes: [AdFreePassQueueItemOutcome] = []
    private(set) var pendingModelConsentEpisodeID: String?
    private(set) var pendingModelConsentByteCount: Int64?
    private(set) var lastFailureEpisodeID: String?
    private(set) var lastFailureMessage: String?
    private var failureMessagesByEpisodeID: [String: String] = [:]
    private var uiProgressMapper = AdFreePassQueueProgressMapper()

    @ObservationIgnored let cancellationSource: AdFreePassCancellationSource
    @ObservationIgnored private var passTask: Task<Void, Never>?
    /// Ownership token for the running drain: bumped by startDrain and
    /// reset() so a cancelled drain resuming after an await cannot mutate a
    /// successor drain's queue state.
    @ObservationIgnored private var drainGeneration = 0
    // Observed (not ignored) so pending-queue mutations — enqueue, drain,
    // removePendingItem — invalidate views reading queueStatus/queueSnapshot.
    private var entries: [QueueEntry] = []
    @ObservationIgnored private var lastPublishedStage: EpisodeAdFreePassStage?
    @ObservationIgnored private var activeTranscriptionEngine: AdFreePassTranscriptionEngine = .productDefault
    @ObservationIgnored private var activeTranscriptionModelIdentity: EpisodeTranscriptionModelIdentity?
    @ObservationIgnored private var stickyComputeProfile: OpenCastTranscriptionComputeProfile?
    @ObservationIgnored private var pausedForEnvironmentalInterrupt = false
    @ObservationIgnored private var lastInterruptedEpisodeID: String?
    /// The running item's analysis store, so a cancel stops its device run.
    @ObservationIgnored private var activeAdAnalyses: EpisodeAdAnalysisStore?
    @ObservationIgnored private let launchPreparationGate: @Sendable () async -> Void
    @ObservationIgnored var onStageChange: (@MainActor (EpisodeAdFreePassStage, AdFreePassQueueContext) -> Void)?
    @ObservationIgnored var onQueueTerminal: (@MainActor (AdFreePassQueueTerminalOutcome) -> Void)?
    /// Shows the key screen for ad detection; called for each item the
    /// listener started that ended needing a key, never for automatic ones.
    @ObservationIgnored var onKeyRequired: (@MainActor (AnalysisKeyRequiredReason) -> Void)?
    @ObservationIgnored var isBackgroundProtected: @MainActor () -> Bool = { false }
    @ObservationIgnored var prefersAppleSpeech: @MainActor () -> Bool = { false }
    /// UI-testing stand-in for the live queue (App Store pipeline shot): the
    /// snapshot and per-episode status come from the override, nothing runs.
    @ObservationIgnored var uiTestQueueOverride: AdFreePassQueueUITestOverride?
    @ObservationIgnored var uiTestEpisodeSnapshotResolver: (@MainActor (String) -> EpisodeListItemSnapshot?)?

    init(
        cancellationSource: AdFreePassCancellationSource = AdFreePassCancellationSource(),
        launchPreparationGate: @escaping @Sendable () async -> Void = {}
    ) {
        self.cancellationSource = cancellationSource
        self.launchPreparationGate = launchPreparationGate
    }

    var activeEpisodeID: String? {
        activeItem?.episodeID
    }

    var queueItems: [AdFreePassQueueItem] {
        entries.map(\.item)
    }

    var isQueuePausedForEnvironmentalInterrupt: Bool {
        queueState == .pausedInterrupted && pausedForEnvironmentalInterrupt
    }

    var queueSnapshot: AdFreePassQueueSnapshot {
        if let uiTestQueueOverride {
            return overriddenQueueSnapshot(uiTestQueueOverride)
        }

        return AdFreePassQueueSnapshot(
            state: queueState,
            activeEpisodeID: activeItem?.episodeID,
            activeEpisodeTitle: activeItem?.episode.title,
            activeArtworkURL: activeItem?.episode.artworkURL,
            currentStage: activeItem != nil ? currentStage : nil,
            finishedItemCount: finishedItemCount,
            totalItemCount: drainTotalItemCount,
            completedCount: drainCompletedCount,
            failedCount: drainFailedCount,
            fractionCompleted: uiProgressMapper.fractionCompleted,
            outcomes: drainOutcomes,
            pendingItems: entries.map(\.item),
            pendingModelConsentByteCount: pendingModelConsentByteCount
        )
    }

    func queueStatus(for episodeID: String) -> AdFreePassQueueEpisodeStatus {
        if let uiTestQueueOverride {
            if uiTestQueueOverride.activeEpisodeID == episodeID {
                return .running
            }
            if let index = uiTestQueueOverride.pendingEpisodeIDs.firstIndex(of: episodeID) {
                return .queued(ahead: index + 1)
            }
            return .notQueued
        }

        if activeItem?.episodeID == episodeID {
            return .running
        }

        if let index = entries.firstIndex(where: { $0.item.episodeID == episodeID }) {
            let ahead = index + (activeItem != nil ? 1 : 0)
            return .queued(ahead: ahead)
        }

        if let outcome = drainOutcomes.last(where: { $0.episodeID == episodeID }) {
            switch outcome.kind {
            case .completed(let zoneCount):
                return .completed(zoneCount: zoneCount)
            case .failed(let message):
                return .failed(message: message)
            case .keyRequired(let reason):
                return .keyRequired(reason)
            }
        }

        return .notQueued
    }

    private func overriddenQueueSnapshot(_ override: AdFreePassQueueUITestOverride) -> AdFreePassQueueSnapshot {
        let activeEpisode = uiTestEpisodeSnapshotResolver?(override.activeEpisodeID)
        let pendingItems = override.pendingEpisodeIDs.enumerated().compactMap { index, episodeID in
            uiTestEpisodeSnapshotResolver?(episodeID).map { episode in
                AdFreePassQueueItem(episode: episode, origin: .manual, enqueuedAt: .now, sequence: index + 1)
            }
        }
        let itemCount = 1 + pendingItems.count
        let activeFraction: Double = switch override.stage {
        case .downloadingEpisode:
            0.1
        case .transcribing(let progress):
            0.2 + 0.6 * (progress.fractionCompleted ?? 0)
        case .analyzing:
            0.9
        default:
            0.5
        }

        return AdFreePassQueueSnapshot(
            state: .running,
            activeEpisodeID: override.activeEpisodeID,
            activeEpisodeTitle: activeEpisode?.title,
            activeArtworkURL: activeEpisode?.artworkURL,
            currentStage: override.stage,
            finishedItemCount: 0,
            totalItemCount: itemCount,
            completedCount: 0,
            failedCount: 0,
            fractionCompleted: activeFraction / Double(itemCount),
            outcomes: [],
            pendingItems: pendingItems,
            pendingModelConsentByteCount: nil
        )
    }

    func presentation(
        for episode: EpisodeListItemSnapshot?,
        downloads: DownloadStore,
        transcriptionModels: TranscriptionModelStore,
        appleSpeechAssets: AppleSpeechAssetStore,
        transcriptions: EpisodeTranscriptionStore,
        adAnalyses: EpisodeAdAnalysisStore,
        currentZoneCount: Int
    ) -> EpisodeAdFreePassPresentation {
        guard let episode else {
            return .unavailable("No episode playing.")
        }

        let episodeID = episode.episodeID

        if pendingModelConsentEpisodeID == episodeID,
           let pendingModelConsentByteCount {
            return .awaitingModelConsent(byteCount: pendingModelConsentByteCount)
        }

        if let queuedPresentation = queuedPresentation(for: episodeID) {
            return queuedPresentation
        }

        if activeEpisodeID == nil,
           let lastFailure = failureMessage(for: episodeID) {
            return .failed(lastFailure)
        }

        if let record = downloads.record(for: episodeID) {
            switch record.state {
            case .downloading:
                return .downloadingEpisode
            case .paused:
                return .failed("Download paused.")
            case .failed, .missing:
                return .failed(record.errorMessage ?? EpisodeDownloadError.missingDownloadedFile.localizedDescription)
            case .completed:
                break
            }
        }

        let presentationEngine = activeEpisodeID == episodeID
            ? activeTranscriptionEngine
            : .productDefault
        let requiresWhisperModel = presentationRequiresWhisperModel(
            for: presentationEngine,
            appleSpeechAssets: appleSpeechAssets
        )

        if activeEpisodeID == episodeID,
           case .installing(_, let fractionCompleted) = appleSpeechAssets.state {
            return .installingSpeechAssets(fractionCompleted: fractionCompleted)
        }

        if requiresWhisperModel {
            switch transcriptionModels.state {
            case .checking:
                return .checkingModel
            case .installing(let progress):
                return .installingModel(progress)
            case .deleting:
                return .modelBusy
            case .failed(let message) where activeEpisodeID == episodeID:
                return .failed(message)
            case .unknown, .notInstalled, .installed, .repairAvailable, .failed:
                break
            }
        }

        let downloadRecord = downloads.record(for: episodeID)
        let transcriptRecord: EpisodeTranscriptRecord
        switch transcriptions.jobState(
            for: episodeID,
            downloadRecord: downloadRecord,
            modelState: transcriptionModels.state,
            modelIdentity: activeEpisodeID == episodeID ? activeTranscriptionModelIdentity : nil,
            requiresInstalledWhisperModel: requiresWhisperModel
        ) {
        case .running(let progress):
            return .transcribing(progress)
        case .failed(let record):
            return .failed(record.errorMessage ?? "Transcript failed.")
        case .cancelled:
            return .failed("Transcript cancelled.")
        case .interrupted(let record):
            return transcriptions.isEnvironmentalInterruption(record) ? .pausedInBackground : .interrupted
        case .completed(let record):
            transcriptRecord = record
        case .unavailable, .downloadRequired, .modelRequired, .modelBusy, .ready:
            if let lastFailure = failureMessage(for: episodeID) {
                return .failed(lastFailure)
            }
            return .idle
        }

        if adAnalyses.isRunning(for: episodeID) {
            return .analyzing
        }

        guard let analysisRecord = adAnalyses.record(for: episodeID) else {
            if let lastFailure = failureMessage(for: episodeID) {
                return .failed(lastFailure)
            }
            if let unavailableMessage = adAnalyses.analysisStartUnavailableMessage {
                return .unavailable(unavailableMessage)
            }
            return .idle
        }

        switch analysisRecord.state {
        case .queued, .running:
            return .analyzing
        case .completed:
            guard let isCurrent = completedAnalysisVerdictIfAvailable(
                for: episodeID,
                transcriptions: transcriptions,
                adAnalyses: adAnalyses
            ) else {
                return .checkingAnalysis
            }
            return isCurrent ? .completed(zoneCount: currentZoneCount) : .outdated
        case .failed:
            guard analysisRecord.transcriptState == .completed,
                  analysisRecord.transcriptUpdatedAt.truncatedToWholeSeconds
                    == transcriptRecord.updatedAt.truncatedToWholeSeconds
            else {
                return .outdated
            }
            return .failed(analysisRecord.errorMessage ?? "Promo/ad analysis failed.")
        }
    }

    func enqueue(
        episode: EpisodeListItemSnapshot,
        origin: AdFreePassQueueOrigin,
        downloads: DownloadStore,
        transcriptionModels: TranscriptionModelStore,
        appleSpeechAssets: AppleSpeechAssetStore,
        transcriptions: EpisodeTranscriptionStore,
        adAnalyses: EpisodeAdAnalysisStore,
        modelContext: ModelContext,
        transcriptionEngine: AdFreePassTranscriptionEngine = .productDefault,
        podcastLanguageCode: String? = nil,
        presentsKeyScreen: Bool = true,
        prepareBackgroundSession: @escaping @MainActor () -> Void = {},
        refreshSkipZones: @escaping @MainActor () async -> Int
    ) {
        let episodeID = episode.episodeID
        // Only a manual start is the listener's; `presentsKeyScreen` is false
        // when the app restarts one for them (an environmental resume).
        let isListenerStart = origin == .manual && presentsKeyScreen

        guard activeItem?.episodeID != episodeID else {
            return
        }

        if let index = entries.firstIndex(where: { $0.item.episodeID == episodeID }) {
            if isListenerStart {
                entries[index].presentsKeyScreen = true
            }
            resumePausedQueueIfHeadReEnqueued(
                episodeID: episodeID,
                prepareBackgroundSession: prepareBackgroundSession
            )
            return
        }

        beginDrainSessionIfNeeded()

        let insertsAtFront = origin == .auto
            || (queueState == .pausedInterrupted && lastInterruptedEpisodeID == episodeID)
        let item = AdFreePassQueueItem(
            episode: episode,
            origin: origin,
            enqueuedAt: .now,
            sequence: nextSequence(front: insertsAtFront)
        )
        let dependencies = PassDependencies(
            downloads: downloads,
            transcriptionModels: transcriptionModels,
            appleSpeechAssets: appleSpeechAssets,
            transcriptions: transcriptions,
            adAnalyses: adAnalyses,
            modelContext: modelContext,
            transcriptionEngine: transcriptionEngine,
            podcastLanguageCode: podcastLanguageCode,
            prepareBackgroundSession: prepareBackgroundSession,
            refreshSkipZones: refreshSkipZones
        )
        let launchPreparation = Task { [weak self] in
            await Task.yield()
            guard let self else {
                return LaunchPreparationOutcome.failed
            }
            return await self.prepareAcceptedItemLaunch(
                item: item,
                dependencies: dependencies
            )
        }
        let entry = QueueEntry(
            item: item,
            deps: dependencies,
            launchPreparation: launchPreparation,
            presentsKeyScreen: isListenerStart
        )
        if insertsAtFront {
            entries.insert(entry, at: 0)
        } else {
            entries.append(entry)
        }
        clearFailure(episodeID: episodeID)

        switch queueState {
        case .idle:
            startDrain()
        case .pausedInterrupted where lastInterruptedEpisodeID == episodeID:
            startDrain()
        case .running, .pausedInterrupted, .awaitingModelConsent:
            break
        }
        SoundLabResponsivenessDiagnostics.mark(
            "queue-state-acknowledged",
            episodeID: episodeID
        )
    }

    func restorePersistedQueue(
        resolveEpisode: (String) -> EpisodeListItemSnapshot?,
        downloads: DownloadStore,
        transcriptionModels: TranscriptionModelStore,
        appleSpeechAssets: AppleSpeechAssetStore,
        transcriptions: EpisodeTranscriptionStore,
        adAnalyses: EpisodeAdAnalysisStore,
        modelContext: ModelContext,
        podcastLanguageCode: (String) -> String?,
        refreshSkipZones: @escaping @MainActor (EpisodeListItemSnapshot) async -> Int
    ) {
        let records: [AdFreePassQueueItemRecord]
        do {
            records = try modelContext.fetch(
                FetchDescriptor<AdFreePassQueueItemRecord>(sortBy: [SortDescriptor(\.sequence)])
            )
        } catch {
            AdFreePassBackgroundRunLog.record("queue restore fetch failed error=\(error.localizedDescription)")
            return
        }
        guard !records.isEmpty else {
            return
        }

        var didDropRecords = false
        for record in records {
            let alreadyQueued = entries.contains { $0.item.episodeID == record.episodeID }
                || activeItem?.episodeID == record.episodeID
            if alreadyQueued {
                continue
            }

            guard let origin = AdFreePassQueueOrigin(rawValue: record.originRawValue),
                  let episode = resolveEpisode(record.episodeID)
            else {
                modelContext.delete(record)
                didDropRecords = true
                continue
            }

            let item = AdFreePassQueueItem(
                episode: episode,
                origin: origin,
                enqueuedAt: record.enqueuedAt,
                sequence: record.sequence
            )
            // Restored items drain foreground-opportunistically; background
            // continuation always requires a fresh explicit tap.
            let entry = QueueEntry(
                item: item,
                deps: PassDependencies(
                    downloads: downloads,
                    transcriptionModels: transcriptionModels,
                    appleSpeechAssets: appleSpeechAssets,
                    transcriptions: transcriptions,
                    adAnalyses: adAnalyses,
                    modelContext: modelContext,
                    transcriptionEngine: .productDefault,
                    podcastLanguageCode: podcastLanguageCode(episode.podcastID),
                    prepareBackgroundSession: {},
                    refreshSkipZones: { await refreshSkipZones(episode) }
                ),
                launchPreparation: nil,
                presentsKeyScreen: false
            )
            entries.append(entry)
        }
        if didDropRecords {
            try? modelContext.save()
        }
        AdFreePassBackgroundRunLog.record("queue restored pending=\(entries.count) records=\(records.count)")

        guard !entries.isEmpty, queueState == .idle else {
            return
        }
        beginDrainSessionIfNeeded()
        startDrain()
    }

    func resumeQueueForEnvironmentalAutoResume() {
        guard isQueuePausedForEnvironmentalInterrupt else {
            return
        }

        pausedForEnvironmentalInterrupt = false
        markHeadPresentsKeyScreen(false)
        if let prepareBackgroundSession = entries.first?.deps.prepareBackgroundSession {
            scheduleResumeLaunchPreparation(
                prepareBackgroundSession: prepareBackgroundSession
            )
        }
        startDrain()
    }

    private func markHeadPresentsKeyScreen(_ presents: Bool) {
        guard !entries.isEmpty else {
            return
        }
        entries[0].presentsKeyScreen = presents
    }

    /// The listener's Resume (the queue's, the card's or the consent
    /// button): the head is theirs from now on, whoever queued it.
    func resumePausedQueue() {
        switch queueState {
        case .pausedInterrupted, .awaitingModelConsent:
            pausedForEnvironmentalInterrupt = false
            markHeadPresentsKeyScreen(true)
            if let prepareBackgroundSession = entries.first?.deps.prepareBackgroundSession {
                scheduleResumeLaunchPreparation(
                    prepareBackgroundSession: prepareBackgroundSession
                )
            }
            startDrain()
        case .idle, .running:
            break
        }
    }

    func handleForegroundReturn() {
        stickyComputeProfile = nil
    }

    func republishCurrentStage() {
        guard let lastPublishedStage else {
            return
        }
        onStageChange?(lastPublishedStage, currentQueueContext)
    }

    func reset() {
        cancellationSource.cancel(reason: .reset)
        passTask?.cancel()
        passTask = nil
        drainGeneration += 1
        cancellationSource.clearTask()
        for entry in entries {
            entry.launchPreparation?.cancel()
        }
        entries = []
        activeItem = nil
        activeAdAnalyses = nil
        currentStage = nil
        queueState = .idle
        drainCompletedCount = 0
        drainFailedCount = 0
        drainOutcomes = []
        uiProgressMapper.reset()
        pendingModelConsentEpisodeID = nil
        pendingModelConsentByteCount = nil
        lastFailureEpisodeID = nil
        lastFailureMessage = nil
        failureMessagesByEpisodeID = [:]
        lastPublishedStage = nil
        activeTranscriptionEngine = .productDefault
        activeTranscriptionModelIdentity = nil
        stickyComputeProfile = nil
        pausedForEnvironmentalInterrupt = false
        lastInterruptedEpisodeID = nil
    }

    func cancelActivePass() {
        cancellationSource.cancel(reason: .userRequest)
        cancelActiveAnalysisRun(reason: .listener)
    }

    /// Stops the active item's device ad-detection run, on-device or a
    /// cloud item's, so its sends stop with the pass: `.listener` ends the
    /// run, `.expiration` keeps it resumable. A run the item is not waiting
    /// on is left alone.
    func cancelActiveAnalysisRun(reason: EpisodeAdAnalysisCancelReason) {
        guard let activeEpisodeID,
              let activeAdAnalyses,
              activeAdAnalyses.isRunning(for: activeEpisodeID)
        else {
            return
        }
        AdFreePassBackgroundRunLog.record("analysis run cancelled episodeID=\(activeEpisodeID) reason=\(reason)")
        activeAdAnalyses.cancelActiveRun(reason: reason)
    }

    func removePendingItem(episodeID: String, modelContext: ModelContext) {
        guard activeItem?.episodeID != episodeID else {
            return
        }

        let countBefore = entries.count
        for entry in entries where entry.item.episodeID == episodeID {
            entry.launchPreparation?.cancel()
        }
        entries.removeAll { $0.item.episodeID == episodeID }
        guard entries.count != countBefore else {
            return
        }

        removePersistedItem(episodeID: episodeID, modelContext: modelContext)
        if pendingModelConsentEpisodeID == episodeID {
            pendingModelConsentEpisodeID = nil
            pendingModelConsentByteCount = nil
        }
        if entries.isEmpty, passTask == nil {
            queueState = .idle
        }
        AdFreePassBackgroundRunLog.record(
            "queue removed pending episodeID=\(episodeID) pending=\(entries.count) state=\(queueState)"
        )
    }

    // MARK: - Queue drain

    private struct PassDependencies {
        let downloads: DownloadStore
        let transcriptionModels: TranscriptionModelStore
        let appleSpeechAssets: AppleSpeechAssetStore
        let transcriptions: EpisodeTranscriptionStore
        let adAnalyses: EpisodeAdAnalysisStore
        let modelContext: ModelContext
        let transcriptionEngine: AdFreePassTranscriptionEngine
        let podcastLanguageCode: String?
        let prepareBackgroundSession: @MainActor () -> Void
        let refreshSkipZones: @MainActor () async -> Int
    }

    private struct QueueEntry {
        let item: AdFreePassQueueItem
        let deps: PassDependencies
        var launchPreparation: Task<LaunchPreparationOutcome, Never>?
        /// Whether the listener asked for this run: a manual start, a manual
        /// re-tap or Resume. Only such a run opens the key screen when it
        /// ends needing a key; automatic, restored and environmentally
        /// resumed runs end silently, the reason shown on the queue.
        var presentsKeyScreen: Bool
    }

    private enum LaunchPreparationOutcome {
        case ready
        case skip
        case failed
    }

    private enum PassOutcome {
        case completed(zoneCount: Int)
        case failed(message: String)
        case awaitingConsent
        case interrupted(environmental: Bool)
        /// Ad detection needed the listener's own key; terminal for the
        /// item, and the drain goes on.
        case keyRequired(AnalysisKeyRequiredReason)
    }

    private var finishedItemCount: Int {
        drainCompletedCount + drainFailedCount
    }

    private var drainTotalItemCount: Int {
        finishedItemCount + (activeItem != nil ? 1 : 0) + entries.count
    }

    private var currentQueueContext: AdFreePassQueueContext {
        AdFreePassQueueContext(
            finishedItemCount: finishedItemCount,
            totalItemCount: max(drainTotalItemCount, 1),
            episodeTitle: activeItem?.episode.title ?? ""
        )
    }

    private func beginDrainSessionIfNeeded() {
        guard queueState == .idle, entries.isEmpty, activeItem == nil else {
            return
        }

        drainCompletedCount = 0
        drainFailedCount = 0
        drainOutcomes = []
        uiProgressMapper.reset()
        currentStage = nil
        lastInterruptedEpisodeID = nil
        pausedForEnvironmentalInterrupt = false
    }

    private func resumePausedQueueIfHeadReEnqueued(
        episodeID: String,
        prepareBackgroundSession: @escaping @MainActor () -> Void
    ) {
        guard entries.first?.item.episodeID == episodeID else {
            return
        }

        switch queueState {
        case .awaitingModelConsent, .pausedInterrupted:
            pausedForEnvironmentalInterrupt = false
            scheduleResumeLaunchPreparation(
                prepareBackgroundSession: prepareBackgroundSession
            )
            startDrain()
        case .idle, .running:
            break
        }
    }

    private func scheduleResumeLaunchPreparation(
        prepareBackgroundSession: @escaping @MainActor () -> Void
    ) {
        guard !entries.isEmpty else {
            return
        }

        let episodeID = entries[0].item.episodeID
        entries[0].launchPreparation = Task {
            await Task.yield()
            await launchPreparationGate()
            await SoundLabResponsivenessDiagnostics.holdLaunchPreparationIfRequested()
            guard !Task.isCancelled else {
                return LaunchPreparationOutcome.skip
            }
            prepareBackgroundSession()
            SoundLabResponsivenessDiagnostics.mark(
                "background-session-armed",
                episodeID: episodeID
            )
            return LaunchPreparationOutcome.ready
        }
    }

    private func prepareAcceptedItemLaunch(
        item: AdFreePassQueueItem,
        dependencies: PassDependencies
    ) async -> LaunchPreparationOutcome {
        await launchPreparationGate()
        await SoundLabResponsivenessDiagnostics.holdLaunchPreparationIfRequested()
        guard !Task.isCancelled else {
            return .skip
        }

        if item.origin == .auto,
           !transcriptIsStaleForDownload(
               episodeID: item.episodeID,
               transcriptions: dependencies.transcriptions,
               downloads: dependencies.downloads
           ),
           await currentCompletedAnalysisVerdict(
               for: item.episodeID,
               transcriptions: dependencies.transcriptions,
               adAnalyses: dependencies.adAnalyses
           ) {
            return .skip
        }

        do {
            try persistItem(item, modelContext: dependencies.modelContext)
            SoundLabResponsivenessDiagnostics.mark(
                "queue-record-persisted",
                episodeID: item.episodeID
            )
        } catch {
            recordFailure(error.localizedDescription, episodeID: item.episodeID)
            return .failed
        }

        dependencies.prepareBackgroundSession()
        SoundLabResponsivenessDiagnostics.mark(
            "background-session-armed",
            episodeID: item.episodeID
        )
        AdFreePassBackgroundRunLog.record(
            "queue enqueued episodeID=\(item.episodeID) origin=\(item.origin.rawValue) pending=\(entries.count) state=\(queueState)"
        )
        return .ready
    }

    private func startDrain() {
        guard passTask == nil, !entries.isEmpty else {
            return
        }

        queueState = .running
        drainGeneration += 1
        let generation = drainGeneration
        let task = Task { [weak self] in
            guard let self else {
                return
            }

            await drainQueue(generation: generation)
        }
        passTask = task
        cancellationSource.start(task)
    }

    private func drainQueue(generation: Int) async {
        // Whisper-perf E1: retain the loaded runtime across items within
        // this drain only (items 2..n skip the ~4.4 s model load when the
        // model + compute profile match). Ended on every drain exit path;
        // failures, profile changes, and memory warnings drop it earlier.
        let retentionStore = entries.first?.deps.transcriptions
        retentionStore?.beginModelRetentionDrain()
        defer {
            if let retentionStore {
                Task { await retentionStore.endModelRetentionDrain() }
            }
        }

        while !entries.isEmpty {
            let pendingEntry = entries[0]
            let launchPreparation = await pendingEntry.launchPreparation?.value ?? .ready
            // A reset() (and possibly a successor drain) may have run during
            // the await; a drain that lost ownership must not touch queue
            // state on its way out.
            guard generation == drainGeneration else {
                return
            }
            guard !Task.isCancelled else {
                endDrain(
                    state: entries.isEmpty ? .idle : .pausedInterrupted,
                    terminal: .interrupted
                )
                return
            }
            guard entries.first?.item.episodeID == pendingEntry.item.episodeID else {
                continue
            }
            if launchPreparation == .skip {
                entries.removeFirst()
                continue
            }
            guard launchPreparation == .ready else {
                let failedEntry = entries.removeFirst()
                let message = failureMessage(for: failedEntry.item.episodeID)
                    ?? "Unable to save the ad detection request."
                drainFailedCount += 1
                drainOutcomes.append(AdFreePassQueueItemOutcome(
                    episodeID: failedEntry.item.episodeID,
                    episodeTitle: failedEntry.item.episode.title,
                    artworkURL: failedEntry.item.episode.artworkURL,
                    kind: .failed(message: message)
                ))
                continue
            }

            let entry = entries.removeFirst()
            activeItem = entry.item
            activeAdAnalyses = entry.deps.adAnalyses
            lastPublishedStage = nil
            activeTranscriptionEngine = entry.deps.transcriptionEngine
            activeTranscriptionModelIdentity = nil
            AdFreePassBackgroundRunLog.record(
                "queue item starting episodeID=\(entry.item.episodeID) origin=\(entry.item.origin.rawValue) finished=\(finishedItemCount) total=\(drainTotalItemCount)"
            )
            AdFreePassBackgroundRunLog.record(
                "transcription engine requested=\(entry.deps.transcriptionEngine.logDescription)"
            )

            let outcome = await runPass(entry)

            guard generation == drainGeneration else {
                return
            }

            if isBackgroundProtected(),
               entry.deps.transcriptions.lastEnvironmentalComputeFallbackEpisodeID == entry.item.episodeID {
                stickyComputeProfile = .cpuOnly
            }
            activeItem = nil
            activeAdAnalyses = nil
            activeTranscriptionEngine = .productDefault
            activeTranscriptionModelIdentity = nil

            switch outcome {
            case .completed(let zoneCount):
                drainCompletedCount += 1
                drainOutcomes.append(AdFreePassQueueItemOutcome(
                    episodeID: entry.item.episodeID,
                    episodeTitle: entry.item.episode.title,
                    artworkURL: entry.item.episode.artworkURL,
                    kind: .completed(zoneCount: zoneCount)
                ))
                removePersistedItem(episodeID: entry.item.episodeID, modelContext: entry.deps.modelContext)
            case .failed(let message):
                drainFailedCount += 1
                drainOutcomes.append(AdFreePassQueueItemOutcome(
                    episodeID: entry.item.episodeID,
                    episodeTitle: entry.item.episode.title,
                    artworkURL: entry.item.episode.artworkURL,
                    kind: .failed(message: message)
                ))
                removePersistedItem(episodeID: entry.item.episodeID, modelContext: entry.deps.modelContext)
            case .awaitingConsent:
                entries.insert(entry, at: 0)
                endDrain(state: .awaitingModelConsent, terminal: .awaitingConsent)
                return
            case .interrupted(let environmental):
                if environmental {
                    entries.insert(entry, at: 0)
                    pausedForEnvironmentalInterrupt = true
                } else {
                    lastInterruptedEpisodeID = entry.item.episodeID
                    removePersistedItem(episodeID: entry.item.episodeID, modelContext: entry.deps.modelContext)
                }
                endDrain(state: entries.isEmpty ? .idle : .pausedInterrupted, terminal: .interrupted)
                return
            case .keyRequired(let reason):
                drainFailedCount += 1
                drainOutcomes.append(AdFreePassQueueItemOutcome(
                    episodeID: entry.item.episodeID,
                    episodeTitle: entry.item.episode.title,
                    artworkURL: entry.item.episode.artworkURL,
                    kind: .keyRequired(reason)
                ))
                removePersistedItem(episodeID: entry.item.episodeID, modelContext: entry.deps.modelContext)
                // A key the listener just removed in AI Services needs no
                // key screen; the queue row says what to do.
                if entry.presentsKeyScreen,
                   !entry.deps.adAnalyses.endedForKeyRemoval(episodeID: entry.item.episodeID) {
                    onKeyRequired?(reason)
                }
            }
        }

        endDrain(
            state: .idle,
            terminal: .drained(completedCount: drainCompletedCount, failedCount: drainFailedCount)
        )
    }

    private func endDrain(state: AdFreePassQueueState, terminal: AdFreePassQueueTerminalOutcome) {
        queueState = state
        passTask = nil
        cancellationSource.clearTask()
        stickyComputeProfile = nil
        AdFreePassBackgroundRunLog.record(
            "queue drain ended state=\(state) terminal=\(terminal) completed=\(drainCompletedCount) failed=\(drainFailedCount) pending=\(entries.count)"
        )
        onQueueTerminal?(terminal)
    }

    private func runPass(_ entry: QueueEntry) async -> PassOutcome {
        let episode = entry.item.episode
        let deps = entry.deps

        let localReservation: EpisodeTranscriptionWorkCoordinator.LocalReservation
        switch deps.transcriptions.reserveLocalWork(
            for: episode.episodeID,
            allowsSameEpisodeAttachment: true
        ) {
        case .success(let value):
            localReservation = value
        case .failure(let conflict):
            return .failed(message: conflict.localizedDescription)
        }
        defer {
            deps.transcriptions.releaseLocalWork(localReservation)
        }

        do {
            let downloadRecord = try await completedDownload(
                for: episode,
                downloads: deps.downloads,
                modelContext: deps.modelContext
            )

            // A completed transcript counts as done for the
            // default path regardless of engine — skip engine resolution and
            // resource setup entirely — unless it describes other audio than
            // this download, whose zones it could never line up with.
            let transcriptDocument: EpisodeTranscriptDocument
            if !deps.transcriptionEngine.isExplicitOverride,
               !transcriptIsStaleForDownload(
                   episodeID: episode.episodeID,
                   transcriptions: deps.transcriptions,
                   downloads: deps.downloads
               ),
               let reusableDocument = await reusableCompletedTranscriptDocument(
                   for: episode.episodeID,
                   transcriptions: deps.transcriptions
               ) {
                AdFreePassBackgroundRunLog.record(
                    "transcript reuse episodeID=\(episode.episodeID) model=\(reusableDocument.modelIdentifier) version=\(reusableDocument.modelVersion)"
                )
                transcriptDocument = reusableDocument
            } else {
                let transcriptionPlan = try await resolvePlanEnsuringResources(
                    for: deps.transcriptionEngine,
                    episodeID: episode.episodeID,
                    podcastLanguageCode: deps.podcastLanguageCode,
                    transcriptionModels: deps.transcriptionModels,
                    appleSpeechAssets: deps.appleSpeechAssets,
                    transcriptions: deps.transcriptions,
                    modelContext: deps.modelContext
                )
                activeTranscriptionModelIdentity = transcriptionPlan.modelIdentity
                transcriptDocument = try await completedTranscript(
                    for: episode,
                    downloadRecord: downloadRecord,
                    downloads: deps.downloads,
                    transcriptionModels: deps.transcriptionModels,
                    transcriptions: deps.transcriptions,
                    transcriptionPlan: transcriptionPlan,
                    localReservation: localReservation,
                    modelContext: deps.modelContext
                )
            }
            try await completedAnalysis(
                for: transcriptDocument,
                transcriptions: deps.transcriptions,
                adAnalyses: deps.adAnalyses,
                allowsExplicitRetry: entry.item.origin == .manual,
                modelContext: deps.modelContext
            )
            let zoneCount = await deps.refreshSkipZones()
            clearFailure(episodeID: episode.episodeID)
            setStage(.completed(zoneCount: zoneCount))
            return .completed(zoneCount: zoneCount)
        } catch PassStop.awaitingModelConsent {
            return .awaitingConsent
        } catch PassStop.keyRequired(let reason) {
            return keyRequiredOutcome(reason, episodeID: episode.episodeID)
        } catch PassStop.interrupted {
            setStage(.interrupted)
            return .interrupted(
                environmental: deps.transcriptions.hasEnvironmentalInterruptionPending(for: episode.episodeID)
            )
        } catch is CancellationError {
            setStage(.interrupted)
            return .interrupted(
                environmental: deps.transcriptions.hasEnvironmentalInterruptionPending(for: episode.episodeID)
            )
        } catch {
            recordFailure(error.localizedDescription, episodeID: episode.episodeID)
            setStage(.failed(message: error.localizedDescription))
            return .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Presentation helpers

    private func queuedPresentation(for episodeID: String) -> EpisodeAdFreePassPresentation? {
        guard let index = entries.firstIndex(where: { $0.item.episodeID == episodeID }) else {
            return nil
        }

        switch queueState {
        case .running:
            return .queued(ahead: index + (activeItem != nil ? 1 : 0))
        case .pausedInterrupted, .awaitingModelConsent, .idle:
            // Paused heads fall through to store-derived presentation so
            // interrupted/consent copy and resume actions surface unchanged.
            return index == 0 ? nil : .queued(ahead: index)
        }
    }

    func hasCurrentCompletedAnalysis(
        for episodeID: String,
        transcriptions: EpisodeTranscriptionStore,
        adAnalyses: EpisodeAdAnalysisStore
    ) -> Bool {
        completedAnalysisVerdictIfAvailable(
            for: episodeID,
            transcriptions: transcriptions,
            adAnalyses: adAnalyses
        ) ?? false
    }

    private func completedAnalysisVerdictIfAvailable(
        for episodeID: String,
        transcriptions: EpisodeTranscriptionStore,
        adAnalyses: EpisodeAdAnalysisStore
    ) -> Bool? {
        guard let analysisRecord = adAnalyses.record(for: episodeID),
              analysisRecord.state == .completed,
              let transcriptRecord = transcriptions.record(for: episodeID),
              transcriptRecord.state == .completed
        else {
            return false
        }

        // Answering for real means decoding + fingerprinting the full
        // transcript document, which scales with episode length — done
        // synchronously here it froze scrolling for every realized row with
        // a completed analysis. The verdict is computed off-main once per
        // (transcript, analysis) revision and cached; until it lands,
        // readers see `false`, which only under-offers "Ads Detected" for
        // the moments before a menu could actually be presented. Gates that
        // must not double-run passes use
        // `currentCompletedAnalysisVerdict` instead.
        let transcriptStamp = transcriptRecord.updatedAt
        let analysisStamp = analysisRecord.updatedAt
        if let verdict = completedAnalysisVerdictsByEpisodeID[episodeID],
           verdict.transcriptRecordUpdatedAt == transcriptStamp,
           verdict.analysisRecordUpdatedAt == analysisStamp {
            return verdict.isCurrent
        }

        scheduleCompletedAnalysisVerdictCompute(
            episodeID: episodeID,
            transcriptions: transcriptions,
            adAnalyses: adAnalyses
        )
        return nil
    }

    /// Definitive variant for no-double-run gates. A cache miss loads both
    /// documents and fingerprints off the caller's actor.
    func currentCompletedAnalysisVerdict(
        for episodeID: String,
        transcriptions: EpisodeTranscriptionStore,
        adAnalyses: EpisodeAdAnalysisStore
    ) async -> Bool {
        guard let analysisRecord = adAnalyses.record(for: episodeID),
              analysisRecord.state == .completed,
              let transcriptRecord = transcriptions.record(for: episodeID),
              transcriptRecord.state == .completed
        else {
            return false
        }

        let transcriptStamp = transcriptRecord.updatedAt
        let analysisStamp = analysisRecord.updatedAt
        if let verdict = completedAnalysisVerdictsByEpisodeID[episodeID],
           verdict.transcriptRecordUpdatedAt == transcriptStamp,
           verdict.analysisRecordUpdatedAt == analysisStamp {
            return verdict.isCurrent
        }

        SoundLabResponsivenessDiagnostics.mark(
            "verdict-documents-load-begin",
            episodeID: episodeID
        )
        async let transcriptLoad = try? transcriptions.loadDocument(for: episodeID)
        async let analysisLoad = try? adAnalyses.loadDocument(for: episodeID)
        let (transcriptDocument, analysisDocument) = await (transcriptLoad, analysisLoad)
        SoundLabResponsivenessDiagnostics.mark(
            "verdict-documents-load-end",
            episodeID: episodeID
        )

        var isCurrent = false
        if let transcriptDocument, let analysisDocument {
            isCurrent = await adAnalyses.isCurrentAnalysisDocumentOffCaller(
                analysisDocument,
                for: transcriptDocument
            )
        }
        if transcriptions.record(for: episodeID)?.updatedAt == transcriptStamp,
           adAnalyses.record(for: episodeID)?.updatedAt == analysisStamp {
            completedAnalysisVerdictsByEpisodeID[episodeID] = CompletedAnalysisVerdict(
                transcriptRecordUpdatedAt: transcriptStamp,
                analysisRecordUpdatedAt: analysisStamp,
                isCurrent: isCurrent
            )
        }
        return isCurrent
    }

    /// Whether the completed transcript describes other audio than the
    /// completed download, as when a dynamic enclosure was downloaded again
    /// with other ads stitched in; its analysis then no longer applies.
    func transcriptIsStaleForDownload(
        episodeID: String,
        transcriptions: EpisodeTranscriptionStore,
        downloads: DownloadStore
    ) -> Bool {
        guard let record = transcriptions.record(for: episodeID), record.state == .completed else {
            return false
        }
        return TranscriptSourceAlignment.transcriptIsStale(
            trustedDownloadSHA256: downloads.completedSourceIdentity(for: episodeID)?.sha256,
            documentSHA256: record.sourceFileSHA256
        )
    }

    private struct CompletedAnalysisVerdict {
        let transcriptRecordUpdatedAt: Date
        let analysisRecordUpdatedAt: Date
        let isCurrent: Bool
    }

    private var completedAnalysisVerdictsByEpisodeID: [String: CompletedAnalysisVerdict] = [:]
    @ObservationIgnored private var completedAnalysisVerdictComputesInFlight: Set<String> = []

    private func scheduleCompletedAnalysisVerdictCompute(
        episodeID: String,
        transcriptions: EpisodeTranscriptionStore,
        adAnalyses: EpisodeAdAnalysisStore
    ) {
        guard !completedAnalysisVerdictComputesInFlight.contains(episodeID) else {
            return
        }
        completedAnalysisVerdictComputesInFlight.insert(episodeID)
        Task { [weak self] in
            guard let self else {
                return
            }
            _ = await self.currentCompletedAnalysisVerdict(
                for: episodeID,
                transcriptions: transcriptions,
                adAnalyses: adAnalyses
            )
            self.completedAnalysisVerdictComputesInFlight.remove(episodeID)
        }
    }

    // MARK: - Persistence

    private var persistedSequenceBounds: (low: Int, high: Int) {
        let sequences = entries.map(\.item.sequence) + (activeItem.map { [$0.sequence] } ?? [])
        return (low: sequences.min() ?? 0, high: sequences.max() ?? 0)
    }

    private func nextSequence(front: Bool) -> Int {
        let bounds = persistedSequenceBounds
        return front ? bounds.low - 1 : bounds.high + 1
    }

    private func persistItem(_ item: AdFreePassQueueItem, modelContext: ModelContext) throws {
        let record = AdFreePassQueueItemRecord(
            episodeID: item.episodeID,
            podcastID: item.episode.podcastID,
            originRawValue: item.origin.rawValue,
            enqueuedAt: item.enqueuedAt,
            sequence: item.sequence
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(record)
            throw error
        }
    }

    private func removePersistedItem(episodeID: String, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<AdFreePassQueueItemRecord>(
            predicate: #Predicate { $0.episodeID == episodeID }
        )
        guard let records = try? modelContext.fetch(descriptor), !records.isEmpty else {
            return
        }

        for record in records {
            modelContext.delete(record)
        }
        try? modelContext.save()
    }

    // MARK: - Pass steps

    private func reusableCompletedTranscriptDocument(
        for episodeID: String,
        transcriptions: EpisodeTranscriptionStore
    ) async -> EpisodeTranscriptDocument? {
        guard let record = transcriptions.record(for: episodeID),
              record.state == .completed
        else {
            return nil
        }
        SoundLabResponsivenessDiagnostics.mark(
            "transcript-document-load-begin",
            episodeID: episodeID
        )
        let document = try? await transcriptions.loadDocument(for: episodeID)
        SoundLabResponsivenessDiagnostics.mark(
            "transcript-document-load-end",
            episodeID: episodeID
        )
        return document
    }

    private func completedDownload(
        for episode: EpisodeListItemSnapshot,
        downloads: DownloadStore,
        modelContext: ModelContext
    ) async throws -> EpisodeDownloadRecord {
        setStage(.downloadingEpisode)

        do {
            return try await downloads.ensureCompletedDownload(
                for: episode,
                modelContext: modelContext,
                onWaitStarted: { try Task.checkCancellation() }
            )
        } catch DownloadStore.CompletedDownloadError.fileMissing {
            throw EpisodeDownloadError.missingDownloadedFile
        } catch let DownloadStore.CompletedDownloadError.notCompleted(state, errorMessage) {
            let message = state == .paused
                ? "Download paused."
                : errorMessage ?? EpisodeDownloadError.missingDownloadedFile.localizedDescription
            throw PassFailure(message)
        }
    }

    private func ensureModelReady(_ transcriptionModels: TranscriptionModelStore) async throws {
        var didStartInstall = false

        while true {
            try Task.checkCancellation()

            let modelChangeSequence = transcriptionModels.changeSequence
            switch transcriptionModels.state {
            case .installed:
                return
            case .repairAvailable, .notInstalled, .unknown:
                didStartInstall = try await installModelIfConsentedOrStop(transcriptionModels)
            case .failed(let message):
                guard !didStartInstall else {
                    throw PassFailure(message)
                }
                didStartInstall = try await installModelIfConsentedOrStop(transcriptionModels)
            case .installing(let progress):
                setStage(.installingModel(progress))
            case .checking, .deleting:
                break
            }

            try await transcriptionModels.waitForChange(after: modelChangeSequence)
        }
    }

    private func resolvePlanEnsuringResources(
        for engine: AdFreePassTranscriptionEngine,
        episodeID: String,
        podcastLanguageCode: String?,
        transcriptionModels: TranscriptionModelStore,
        appleSpeechAssets: AppleSpeechAssetStore,
        transcriptions: EpisodeTranscriptionStore,
        modelContext: ModelContext
    ) async throws -> EpisodeTranscriptionPlan {
        // Follows the global engine preference, like Generate; an interrupted
        // Whisper checkpoint stays on Whisper so its progress is kept.
        let resolver = EpisodeTranscriptionPlanResolver(
            transcriptionModels: transcriptionModels,
            appleSpeechAssets: appleSpeechAssets,
            prefersRevocationDurableEngine: !prefersAppleSpeech()
                || transcriptions.hasResumableWhisperCheckpoint(for: episodeID)
        )

        switch engine {
        case .selectedWhisperModel:
            try await ensureModelReady(transcriptionModels)
        case .productDefault, .appleSpeech:
            break
        }

        let assetStageTask = engine == .productDefault
            ? observeAssetInstallStages(appleSpeechAssets)
            : nil
        defer {
            assetStageTask?.cancel()
        }

        do {
            return try await resolver.resolve(
                requestedEngine: engine,
                podcastLanguageCode: podcastLanguageCode
            )
        } catch EpisodeTranscriptionError.missingSpeechModel where engine == .productDefault {
            // Whisper fallback with no installed model: run the existing
            // consent/install flow, then re-resolve.
            try await ensureModelReady(transcriptionModels)
            return try await resolver.resolve(
                requestedEngine: engine,
                podcastLanguageCode: podcastLanguageCode
            )
        }
    }

    private func observeAssetInstallStages(
        _ appleSpeechAssets: AppleSpeechAssetStore
    ) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                let sequence = appleSpeechAssets.changeSequence
                if case .installing(_, let fractionCompleted) = appleSpeechAssets.state {
                    self?.setStage(.installingSpeechAssets(fractionCompleted: fractionCompleted))
                }
                do {
                    try await appleSpeechAssets.waitForChange(after: sequence)
                } catch {
                    return
                }
            }
        }
    }

    private func completedTranscript(
        for episode: EpisodeListItemSnapshot,
        downloadRecord: EpisodeDownloadRecord,
        downloads: DownloadStore,
        transcriptionModels: TranscriptionModelStore,
        transcriptions: EpisodeTranscriptionStore,
        transcriptionPlan: EpisodeTranscriptionPlan,
        localReservation: EpisodeTranscriptionWorkCoordinator.LocalReservation,
        modelContext: ModelContext
    ) async throws -> EpisodeTranscriptDocument {
        var didStartTranscription = false

        while true {
            try Task.checkCancellation()

            let modelChangeSequence = transcriptionModels.changeSequence
            let transcriptionChangeSequence = transcriptions.changeSequence
            let state = transcriptions.jobState(
                for: episode.episodeID,
                downloadRecord: downloadRecord,
                modelState: transcriptionModels.state,
                modelIdentity: transcriptionPlan.isEngineStrict ? transcriptionPlan.modelIdentity : nil,
                requiresInstalledWhisperModel: transcriptionPlan.requiresInstalledWhisperModel
            )
            switch state {
            case .completed where !didStartTranscription && transcriptIsStaleForDownload(
                episodeID: episode.episodeID,
                transcriptions: transcriptions,
                downloads: downloads
            ):
                try await startTranscriptionOrThrowOnSecondAttempt(
                    secondPassError: PassFailure(FailureMessage.transcriptUnavailable),
                    didStartTranscription: &didStartTranscription,
                    episode: episode,
                    downloadRecord: downloadRecord,
                    downloads: downloads,
                    transcriptionModels: transcriptionModels,
                    transcriptions: transcriptions,
                    transcriptionPlan: transcriptionPlan,
                    localReservation: localReservation,
                    modelContext: modelContext
                )
            case .completed:
                SoundLabResponsivenessDiagnostics.mark(
                    "transcript-document-load-begin",
                    episodeID: episode.episodeID
                )
                guard let document = try? await transcriptions.loadDocument(
                    for: episode.episodeID
                ) else {
                    throw EpisodeTranscriptionError.transcriptDocumentMissing
                }
                SoundLabResponsivenessDiagnostics.mark(
                    "transcript-document-load-end",
                    episodeID: episode.episodeID
                )
                return document
            case .running(let progress):
                setStage(.transcribing(progress))
                break
            case .interrupted:
                try await startTranscriptionOrThrowOnSecondAttempt(
                    secondPassError: PassStop.interrupted,
                    didStartTranscription: &didStartTranscription,
                    episode: episode,
                    downloadRecord: downloadRecord,
                    downloads: downloads,
                    transcriptionModels: transcriptionModels,
                    transcriptions: transcriptions,
                    transcriptionPlan: transcriptionPlan,
                    localReservation: localReservation,
                    modelContext: modelContext
                )
            case .ready, .failed, .cancelled:
                try await startTranscriptionOrThrowOnSecondAttempt(
                    secondPassError: PassFailure(transcriptionFailureMessage(state)),
                    didStartTranscription: &didStartTranscription,
                    episode: episode,
                    downloadRecord: downloadRecord,
                    downloads: downloads,
                    transcriptionModels: transcriptionModels,
                    transcriptions: transcriptions,
                    transcriptionPlan: transcriptionPlan,
                    localReservation: localReservation,
                    modelContext: modelContext
                )
            case .downloadRequired:
                throw EpisodeTranscriptionError.downloadNotComplete
            case .modelRequired:
                throw EpisodeTranscriptionError.missingSpeechModel
            case .modelBusy:
                try await transcriptionModels.waitForChange(after: modelChangeSequence)
                continue
            case .unavailable:
                throw PassFailure(FailureMessage.transcriptUnavailable)
            }

            try await transcriptions.waitForChange(after: transcriptionChangeSequence)
        }
    }

    private func completedAnalysis(
        for transcriptDocument: EpisodeTranscriptDocument,
        transcriptions: EpisodeTranscriptionStore,
        adAnalyses: EpisodeAdAnalysisStore,
        allowsExplicitRetry: Bool,
        modelContext: ModelContext
    ) async throws {
        if !allowsExplicitRetry, let blocked = try await adAnalyses.automaticReplayError(for: transcriptDocument) { throw blocked }
        let episodeID = transcriptDocument.episodeID
        let progressUpdates = followAnalysisProgress(for: episodeID, adAnalyses: adAnalyses)
        defer {
            progressUpdates.cancel()
        }
        var didStartAnalysis = false

        do {
            while true {
                try Task.checkCancellation()

                let analysisChangeSequence = adAnalyses.changeSequence
                if adAnalyses.isRunning(for: episodeID) {
                    publishAnalyzing(steps: analysisSteps(for: episodeID, adAnalyses: adAnalyses))
                } else if let record = adAnalyses.record(for: episodeID) {
                    switch record.state {
                    case .queued, .running:
                        // No run holds it: a cancelled run leaves its record
                        // running until a start (or the next launch) moves
                        // it on.
                        try startAnalysisOrThrowOnSecondAttempt(
                            didStartAnalysis: &didStartAnalysis,
                            transcriptDocument: transcriptDocument,
                            transcriptions: transcriptions,
                            adAnalyses: adAnalyses,
                            allowsExplicitRetry: allowsExplicitRetry,
                            modelContext: modelContext
                        )
                    case .completed:
                        if await adAnalyses.hasCurrentCompletedAnalysis(
                            for: transcriptDocument
                        ) {
                            return
                        }
                        try startAnalysisOrThrowOnSecondAttempt(
                            didStartAnalysis: &didStartAnalysis,
                            transcriptDocument: transcriptDocument,
                            transcriptions: transcriptions,
                            adAnalyses: adAnalyses,
                            allowsExplicitRetry: allowsExplicitRetry,
                            modelContext: modelContext
                        )
                    case .failed:
                        guard !didStartAnalysis else {
                            if let reason = record.failureKind?.keyRequiredReason {
                                throw PassStop.keyRequired(reason)
                            }
                            throw PassFailure(
                                record.errorMessage
                                    ?? adAnalyses.lastErrorMessage(for: episodeID)
                                    ?? FailureMessage.analysisFailed
                            )
                        }
                        try startAnalysisOrThrowOnSecondAttempt(
                            didStartAnalysis: &didStartAnalysis,
                            transcriptDocument: transcriptDocument,
                            transcriptions: transcriptions,
                            adAnalyses: adAnalyses,
                            allowsExplicitRetry: allowsExplicitRetry,
                            modelContext: modelContext
                        )
                    }
                } else {
                    if let unavailableMessage = adAnalyses.analysisStartUnavailableMessage {
                        throw PassFailure(unavailableMessage)
                    }
                    guard !didStartAnalysis else {
                        throw PassFailure(
                            adAnalyses.lastErrorMessage(for: episodeID)
                                ?? FailureMessage.analysisFailed
                        )
                    }
                    try startAnalysisOrThrowOnSecondAttempt(
                        didStartAnalysis: &didStartAnalysis,
                        transcriptDocument: transcriptDocument,
                        transcriptions: transcriptions,
                        adAnalyses: adAnalyses,
                        allowsExplicitRetry: allowsExplicitRetry,
                        modelContext: modelContext
                    )
                }

                try await adAnalyses.waitForChange(after: analysisChangeSequence)
            }
        } catch let error as CancellationError {
            // The store owns the run, not the pass: stop its sends with the
            // pass. An expired card keeps the run resumable.
            cancelActiveAnalysisRun(
                reason: cancellationSource.lastCancellationReason == .sessionExpiration ? .expiration : .listener
            )
            throw error
        }
    }

    /// Every start is automatic for the store: the key screen shows once
    /// per drain from the drain itself, whatever started the item.
    private func startAnalysisOrThrowOnSecondAttempt(
        didStartAnalysis: inout Bool,
        transcriptDocument: EpisodeTranscriptDocument,
        transcriptions: EpisodeTranscriptionStore,
        adAnalyses: EpisodeAdAnalysisStore,
        allowsExplicitRetry: Bool,
        modelContext: ModelContext
    ) throws {
        let episodeID = transcriptDocument.episodeID
        guard !didStartAnalysis else {
            if let reason = adAnalyses.record(for: episodeID)?.failureKind?.keyRequiredReason {
                throw PassStop.keyRequired(reason)
            }
            throw PassFailure(
                adAnalyses.lastErrorMessage(for: episodeID)
                    ?? FailureMessage.analysisFailed
            )
        }

        adAnalyses.startAnalysis(
            transcript: transcriptDocument,
            transcriptState: transcriptions.record(for: episodeID)?.state,
            retryFailed: allowsExplicitRetry,
            presentsKeyScreen: false,
            modelContext: modelContext
        )
        didStartAnalysis = true
        publishAnalyzing(steps: analysisSteps(for: episodeID, adAnalyses: adAnalyses))
    }

    private func analysisSteps(
        for episodeID: String,
        adAnalyses: EpisodeAdAnalysisStore
    ) -> EpisodeAdFreePassAnalysisSteps? {
        adAnalyses.analysisProgress(for: episodeID).map(EpisodeAdFreePassAnalysisSteps.init)
    }

    /// Publishes the analyzing stage with the run's steps. A run that has
    /// not counted its steps yet, or has just ended, keeps the steps shown.
    private func publishAnalyzing(steps: EpisodeAdFreePassAnalysisSteps?) {
        if steps == nil, case .analyzing(.some) = lastPublishedStage {
            return
        }
        setStage(.analyzing(steps: steps))
    }

    /// Follows the store's step count while the pass waits on its run, so
    /// the queue and the card move with each answered step.
    private func followAnalysisProgress(
        for episodeID: String,
        adAnalyses: EpisodeAdAnalysisStore
    ) -> Task<Void, Never> {
        Task { [weak self] in
            for await steps in Observations({
                adAnalyses.analysisProgress(for: episodeID).map(EpisodeAdFreePassAnalysisSteps.init)
            }) {
                guard !Task.isCancelled, let self else {
                    return
                }
                guard case .analyzing = lastPublishedStage else {
                    continue
                }
                publishAnalyzing(steps: steps)
            }
        }
    }

    /// The item ends needing the listener's key: the card names the reason
    /// and the drain goes on.
    private func keyRequiredOutcome(_ reason: AnalysisKeyRequiredReason, episodeID: String) -> PassOutcome {
        let message = EpisodePipelineState.analysisFailedMessage(for: EpisodeAnalysisFailureKind(keyRequired: reason))
        recordFailure(message, episodeID: episodeID)
        setStage(.failed(message: message))
        return .keyRequired(reason)
    }

    private func installModelIfConsentedOrStop(
        _ transcriptionModels: TranscriptionModelStore
    ) async throws -> Bool {
        guard pendingModelConsentEpisodeID == activeEpisodeID else {
            let byteCount = try await transcriptionModels.selectedModelRemoteByteCount()
            pendingModelConsentByteCount = byteCount
            pendingModelConsentEpisodeID = activeEpisodeID
            setStage(.awaitingModelDownloadConsent(byteCount: byteCount))
            throw PassStop.awaitingModelConsent
        }

        pendingModelConsentEpisodeID = nil
        pendingModelConsentByteCount = nil
        transcriptionModels.installPinnedModel()
        return true
    }

    private func startTranscriptionOrThrowOnSecondAttempt(
        secondPassError: any Error,
        didStartTranscription: inout Bool,
        episode: EpisodeListItemSnapshot,
        downloadRecord: EpisodeDownloadRecord,
        downloads: DownloadStore,
        transcriptionModels: TranscriptionModelStore,
        transcriptions: EpisodeTranscriptionStore,
        transcriptionPlan: EpisodeTranscriptionPlan,
        localReservation: EpisodeTranscriptionWorkCoordinator.LocalReservation,
        modelContext: ModelContext
    ) async throws {
        guard !didStartTranscription else {
            throw secondPassError
        }

        try await startTranscription(
            episode,
            downloadRecord: downloadRecord,
            downloads: downloads,
            transcriptionModels: transcriptionModels,
            transcriptions: transcriptions,
            transcriptionPlan: transcriptionPlan,
            localReservation: localReservation,
            modelContext: modelContext
        )
        didStartTranscription = true
    }

    private func startTranscription(
        _ episode: EpisodeListItemSnapshot,
        downloadRecord: EpisodeDownloadRecord,
        downloads: DownloadStore,
        transcriptionModels: TranscriptionModelStore,
        transcriptions: EpisodeTranscriptionStore,
        transcriptionPlan: EpisodeTranscriptionPlan,
        localReservation: EpisodeTranscriptionWorkCoordinator.LocalReservation,
        modelContext: ModelContext
    ) async throws {
        guard let localFileURL = downloads.localFileURL(for: downloadRecord),
              downloads.downloadedFileExists(for: downloadRecord)
        else {
            try? downloads.markDownloadedFileMissing(downloadRecord, modelContext: modelContext)
            throw EpisodeTranscriptionError.missingDownloadedFile
        }

        // After a classified cpuOnly fallback inside a protected
        // drain, subsequent whisper items skip the doomed default attempt.
        let initialComputeProfile: OpenCastTranscriptionComputeProfile =
            transcriptionPlan.runEngine == .whisper
                ? (stickyComputeProfile ?? .backgroundSafe)
                : .backgroundSafe

        transcriptions.startTranscription(
            episode,
            downloadRecord: downloadRecord,
            localFileURL: localFileURL,
            engine: transcriptionPlan.runEngine,
            modelIdentity: transcriptionPlan.modelIdentity,
            languageCode: transcriptionPlan.languageCode,
            runLanguageCode: transcriptionPlan.runLanguageCode,
            initialComputeProfile: initialComputeProfile,
            localReservation: localReservation,
            modelContext: modelContext
        )
    }

    private func presentationRequiresWhisperModel(
        for engine: AdFreePassTranscriptionEngine,
        appleSpeechAssets: AppleSpeechAssetStore
    ) -> Bool {
        switch engine {
        case .productDefault:
            !prefersAppleSpeech() || !appleSpeechAssets.isTranscriberAvailable
        case .selectedWhisperModel:
            true
        case .appleSpeech:
            false
        }
    }

    private func transcriptionFailureMessage(_ state: EpisodeTranscriptionJobState) -> String {
        switch state {
        case .failed(let record):
            record.errorMessage ?? FailureMessage.transcriptFailed
        case .cancelled:
            FailureMessage.transcriptCancelled
        default:
            FailureMessage.transcriptFailed
        }
    }

    private func failureMessage(for episodeID: String) -> String? {
        failureMessagesByEpisodeID[episodeID]
    }

    private func recordFailure(_ message: String, episodeID: String) {
        failureMessagesByEpisodeID[episodeID] = message
        lastFailureEpisodeID = episodeID
        lastFailureMessage = message
    }

    private func clearFailure(episodeID: String) {
        failureMessagesByEpisodeID[episodeID] = nil
        if lastFailureEpisodeID == episodeID {
            lastFailureEpisodeID = nil
            lastFailureMessage = nil
        }
    }

    private func setStage(_ stage: EpisodeAdFreePassStage) {
        guard lastPublishedStage != stage else {
            return
        }

        let isFirstConcreteStage = lastPublishedStage == nil
        lastPublishedStage = stage
        currentStage = stage
        if isFirstConcreteStage {
            SoundLabResponsivenessDiagnostics.mark(
                "coordinator-first-concrete-stage",
                episodeID: activeEpisodeID
            )
        }
        let context = currentQueueContext
        _ = uiProgressMapper.update(for: stage, queueContext: context)
        onStageChange?(stage, context)
    }

    private enum PassStop: Error {
        case awaitingModelConsent
        case interrupted
        case keyRequired(AnalysisKeyRequiredReason)
    }

    private struct PassFailure: LocalizedError {
        var message: String

        init(_ message: String) {
            self.message = message
        }

        var errorDescription: String? {
            message
        }
    }

}
