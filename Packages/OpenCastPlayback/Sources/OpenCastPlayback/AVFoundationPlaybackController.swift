@preconcurrency import AVFoundation
import Foundation
import Observation
import OpenCastCore
import OpenCastVoiceBoost
import os

typealias VoiceBoostAudioTapFactory = (
    VoiceBoostConfiguration,
    VoiceBoostAudioTapDiagnostics?
) throws -> VoiceBoostAudioTap

public typealias PlaybackRateChangeRequestHandler = @MainActor (Float) -> Void
public typealias PlaybackEpisodeFinishedHandler = @MainActor (Episode, PlaybackCompletionPolicy) -> Void

@Observable
public final class AVFoundationPlaybackController {
    private static let autoSkipSettleTolerance: TimeInterval = 0.05
    private static let sleepTimerRearmWindow: TimeInterval = 5 * 60
    /// Room for the swap's boundary observer to be armed before its cut.
    private static let smartSpeedSwapLeadTime: TimeInterval = 0.15
    private static let logger = Logger(
        subsystem: "OpenCastPlayback",
        category: "AVFoundationPlaybackController"
    )

    public private(set) var snapshot = PlaybackSnapshot()
    /// Counts player-item installs and the unload: a load, a download
    /// switch, a failed-item rebuild, `unload()`. Readers that derive state
    /// from the item (chapters) key on it, so a list read off one item never
    /// outlives that item.
    public private(set) var currentItemGeneration = 0
    public private(set) var currentEpisode: Episode?
    public private(set) var state: PlaybackState = .idle
    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval?
    public private(set) var progress: Double = 0
    public private(set) var progressBoundaryID = 0
    public private(set) var rate: Float = 1
    public private(set) var sleepTimerEndsAt: Date?
    public private(set) var sleepTimerMode = PlaybackSleepTimerMode.off
    public private(set) var skipZones: [PlaybackSkipZone] = []
    public private(set) var lastAutoSkipEvent: PlaybackAutoSkipEvent?
    public private(set) var skipBackwardInterval: TimeInterval = PlaybackSkipInterval.backward
    public private(set) var skipForwardInterval: TimeInterval = PlaybackSkipInterval.forward
    public private(set) var playbackDiagnosticsText = ""

    /// Replaced after a media services reset; see `replacePlayer()`.
    @ObservationIgnored private var player = AVPlayer()
    @ObservationIgnored private let mediaSession: SystemPlaybackMediaSession
    @ObservationIgnored private var timeObserver: PlayerTimeObserver?
    @ObservationIgnored private var outroBoundaryObserver: PlayerTimeObserver?
    @ObservationIgnored private var outroBoundaryCutoff: TimeInterval?
    @ObservationIgnored private var skipZoneBoundaryObservers: [PlayerTimeObserver] = []
    @ObservationIgnored private var currentItemObservationGeneration = 0
    @ObservationIgnored private var mediaClockObservers: [UUID: PlayerTimeObserver] = [:]
    @ObservationIgnored private var mediaClockContinuations: [UUID: AsyncStream<PlaybackMediaClockSample>.Continuation] = [:]
    @ObservationIgnored private var mediaClockIntervals: [UUID: TimeInterval] = [:]
    @ObservationIgnored private var currentItemEndObserver: NSObjectProtocol?
    @ObservationIgnored private var currentItemPlaybackStalledObserver: NSObjectProtocol?
    @ObservationIgnored private var currentItemDurationObservation: NSKeyValueObservation?
    @ObservationIgnored private var currentItemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var currentItemLikelyToKeepUpObservation: NSKeyValueObservation?
    @ObservationIgnored private var currentItemBufferEmptyObservation: NSKeyValueObservation?
    @ObservationIgnored private var playerTimeControlStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var audioSessionInterruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var audioSessionRouteChangeObserver: NSObjectProtocol?
    @ObservationIgnored private var audioSessionMediaServicesResetObserver: NSObjectProtocol?
    @ObservationIgnored private var audioSessionSecondaryAudioObserver: NSObjectProtocol?
    @ObservationIgnored private var audioSessionOutputVolumeObservation: NSKeyValueObservation?
    @ObservationIgnored private var currentLevelMeter: PlaybackLevelMeterTap?
    @ObservationIgnored private var currentVoiceBoostTap: VoiceBoostAudioTap?
    @ObservationIgnored private var pendingVoiceBoostContinuationState: VoiceBoostContinuationState?
    @ObservationIgnored private var voiceBoostTrackLoadTask: Task<Void, Never>?
    @ObservationIgnored private let voiceBoostTapDiagnostics: VoiceBoostAudioTapDiagnostics?
    @ObservationIgnored private let voiceBoostAudioTapFactory: VoiceBoostAudioTapFactory
    @ObservationIgnored private let audioSessionActivation: PlaybackAudioSessionActivation
    @ObservationIgnored private let audioSessionDeactivation: PlaybackAudioSessionDeactivation
    @ObservationIgnored private var voiceBoostConfiguration = VoiceBoostConfiguration.default
    @ObservationIgnored var isAudioSessionActive = false
    @ObservationIgnored private var audioSessionActivationTask: Task<Void, Never>?
    @ObservationIgnored private var audioSessionActivationGeneration = 0
    @ObservationIgnored private var audioSessionDeactivationTask: Task<Void, Never>?
    @ObservationIgnored private var isPlaybackRequested = false
    @ObservationIgnored private var shouldResumeAfterInterruption = false
    @ObservationIgnored private var sleepTimerTask: Task<Void, Never>?
    @ObservationIgnored private var expiredSleepTimerMode: PlaybackSleepTimerMode?
    @ObservationIgnored private var sleepTimerRearmDeadline: Date?
    @ObservationIgnored private var remotePlaybackRateChangeHandler: PlaybackRateChangeRequestHandler?
    @ObservationIgnored private var episodeFinishedHandler: PlaybackEpisodeFinishedHandler?
    @ObservationIgnored private var playbackPositionProtection = PlaybackPositionProtection()
    @ObservationIgnored private var playbackAdSkipPolicy = PlaybackAdSkipPolicy()
    @ObservationIgnored private var playbackFailureRecoveryPolicy = PlaybackFailureRecoveryPolicy()
    /// Set when a media-services-reset item failure replaced the player, and
    /// cleared once an item is ready, so a server that keeps failing ends in
    /// a failure rather than a replacement loop.
    @ObservationIgnored private var hasReplacedPlayerForFailedItem = false
    @ObservationIgnored private var autoSkipEventSequence = 0
    @ObservationIgnored private var pendingAutoSkipTarget: TimeInterval?
    @ObservationIgnored private var episodeBoundaries = PlaybackEpisodeBoundaries.disabled
    @ObservationIgnored private var hasFinishedCurrentEpisode = false
    @ObservationIgnored private var isPlaybackDiagnosticsEnabled = false
    @ObservationIgnored private var playbackDiagnosticsEvents: [String] = []
    @ObservationIgnored private var eventLogHandler: (@MainActor (String) -> Void)?
    @ObservationIgnored private var currentItemLocalFileIdentity: PlaybackLocalFileIdentity?
    @ObservationIgnored private var currentItemSourceURL: URL?
    @ObservationIgnored private var isSmartSpeedEnabled = false
    @ObservationIgnored private var smartSpeedTask: Task<Void, Never>?
    /// Set while the trimmed copy is built from saved pauses. That takes
    /// milliseconds, so playback waits for it rather than starting on the
    /// file and swapping moments later.
    @ObservationIgnored private var isAwaitingSmartSpeedItem = false
    /// Armed at the next cut while the file plays, so the swap to the
    /// trimmed copy lands in a pause instead of mid-word.
    @ObservationIgnored private var smartSpeedSwapObserver: PlayerTimeObserver?
    /// Set from a mid-play swap until the trimmed copy plays. The listener
    /// asked for nothing, so the state stays playing rather than buffering.
    @ObservationIgnored private var isSwappingSmartSpeedItem = false
    @ObservationIgnored private var smartSpeedSwapStartedAt: ContinuousClock.Instant?
    /// The last download trimmed for Smart Speed, kept so toggling or a
    /// rebuild of the same file need not analyze it again.
    @ObservationIgnored private var smartSpeedSource: SmartSpeedSource?
    /// Set while the player item is the trimmed copy. AVPlayer then runs on
    /// the shortened clock; see `episodeTime(fromPlayer:)`.
    @ObservationIgnored private var currentSmartSpeedItem: SmartSpeedCompositionBuilder.Result?
    @ObservationIgnored var playbackStartBehaviorObserver: ((PlaybackStartBehavior) -> Void)?

    public convenience init(
        voiceBoostTapDiagnostics: VoiceBoostAudioTapDiagnostics? = nil,
        nowPlayingArtworkLoader: (any NowPlayingArtworkLoading)? = nil
    ) {
        self.init(
            voiceBoostTapDiagnostics: voiceBoostTapDiagnostics,
            nowPlayingArtworkLoader: nowPlayingArtworkLoader,
            voiceBoostAudioTapFactory: {
                try VoiceBoostAudioTap(configuration: $0, diagnostics: $1)
            }
        )
    }

    init(
        voiceBoostTapDiagnostics: VoiceBoostAudioTapDiagnostics?,
        nowPlayingArtworkLoader: (any NowPlayingArtworkLoading)? = nil,
        audioSessionActivation: @escaping PlaybackAudioSessionActivation = {
            try await activateSystemPlaybackAudioSession()
        },
        audioSessionDeactivation: @escaping PlaybackAudioSessionDeactivation = {
            try await deactivateSystemPlaybackAudioSession()
        },
        voiceBoostAudioTapFactory: @escaping VoiceBoostAudioTapFactory = {
            try VoiceBoostAudioTap(configuration: $0, diagnostics: $1)
        }
    ) {
        self.mediaSession = SystemPlaybackMediaSession(
            artworkLoader: nowPlayingArtworkLoader ?? DefaultNowPlayingArtworkLoader()
        )
        self.voiceBoostTapDiagnostics = voiceBoostTapDiagnostics
        self.voiceBoostAudioTapFactory = voiceBoostAudioTapFactory
        self.audioSessionActivation = audioSessionActivation
        self.audioSessionDeactivation = audioSessionDeactivation
        configurePlayer()
        installAudioSessionObservers()
        installRemoteCommands()
    }

    isolated deinit {
        for observer in mediaClockObservers.values {
            player.removeTimeObserver(observer.token)
        }
        mediaClockObservers.removeAll()
        for continuation in mediaClockContinuations.values {
            continuation.finish()
        }
        mediaClockContinuations.removeAll()
        removeCurrentItemObservations()
        playerTimeControlStatusObservation?.invalidate()
        removeAudioSessionObservers()
        voiceBoostTrackLoadTask?.cancel()
        smartSpeedTask?.cancel()
        audioSessionActivationTask?.cancel()
        sleepTimerTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentVoiceBoostTap = nil
        currentLevelMeter = nil
        mediaSession.clear()
        #if os(iOS) || os(tvOS) || os(visionOS)
        if isAudioSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }

    public func load(
        _ episode: Episode,
        startPosition: TimeInterval = 0,
        boundaries: PlaybackEpisodeBoundaries = .disabled
    ) throws {
        guard let audioURL = episode.audioURL else {
            throw OpenCastCoreError.missingAudioURL
        }

        removeCurrentItemObservations()
        playbackPositionProtection.clear()
        voiceBoostTrackLoadTask?.cancel()
        voiceBoostTrackLoadTask = nil
        isPlaybackRequested = false
        clearExpiredSleepTimerRearm()
        playbackFailureRecoveryPolicy.reset()
        hasReplacedPlayerForFailedItem = false
        playbackAdSkipPolicy.setZones([])
        autoSkipEventSequence = 0
        lastAutoSkipEvent = nil
        pendingAutoSkipTarget = nil
        episodeBoundaries = boundaries
        hasFinishedCurrentEpisode = false
        if sleepTimerMode == .endOfEpisode {
            clearSleepTimer()
        }

        let episodeDuration = finitePositive(episode.duration)
        let initialPosition = clampPlaybackPosition(startPosition, to: episodeDuration)
        replaceSnapshot(PlaybackSnapshot(
            state: .loading,
            currentEpisode: episode,
            position: initialPosition,
            duration: episodeDuration,
            rate: snapshot.rate,
            sleepTimerEndsAt: snapshot.sleepTimerEndsAt,
            progressBoundaryID: snapshot.progressBoundaryID
        ))

        let playerItem = makePlayerItem(audioURL: audioURL)
        player.replaceCurrentItem(with: playerItem)
        observeCurrentItem(playerItem)
        refreshOutroBoundaryObserver()

        if snapshot.position > 0 {
            seekPlayer(to: snapshot.position, mode: .restoredPosition)
        }

        snapshot.state = .paused
        if snapshot.position == 0 {
            evaluateAutoSkip(
                previousPosition: -Double.ulpOfOne,
                position: 0,
                cause: .playStart
            )
        }
        recordDiagnosticsEvent("loaded episode start=\(diagnosticsTime(snapshot.position)) url=\(audioURL.absoluteString)")
        publishPlaybackState()
        refreshSmartSpeed()
    }

    public func updateVoiceBoostConfiguration(_ configuration: VoiceBoostConfiguration) {
        let wasEnabled = voiceBoostConfiguration.isEnabled
        voiceBoostConfiguration = configuration
        if !configuration.isEnabled {
            voiceBoostTrackLoadTask?.cancel()
            voiceBoostTrackLoadTask = nil
        }
        if let currentVoiceBoostTap {
            currentVoiceBoostTap.update(configuration: configuration)
            if configuration.isEnabled, !wasEnabled,
               let currentItem = player.currentItem,
               currentItem.audioMix?.inputParameters.first?.trackID == kCMPersistentTrackID_Invalid,
               let asset = currentItem.asset as? AVURLAsset {
                scheduleTrackBoundVoiceBoostTapInstall(for: currentItem, asset: asset)
            }
        } else if configuration.isEnabled, let currentItem = player.currentItem {
            installVoiceBoostTap(on: currentItem, continuationState: pendingVoiceBoostContinuationState)
            if let asset = currentItem.asset as? AVURLAsset {
                scheduleTrackBoundVoiceBoostTapInstall(for: currentItem, asset: asset)
            }
        }
    }

    public func loadCurrentItemChapters() async throws -> [EpisodeChapter] {
        guard let asset = player.currentItem?.asset else {
            return []
        }
        return try await AVAssetChapterReader.chapters(in: asset)
    }

    /// Replaces this episode's audio without starting a new listening session.
    /// Download completion can arrive while paused, buffering, or interrupted.
    @discardableResult
    public func useDownloadedAudio(at fileURL: URL, for episodeID: EpisodeID) -> Bool {
        guard fileURL.isFileURL,
              var episode = snapshot.currentEpisode,
              episode.id == episodeID
        else {
            return false
        }
        let fileIdentity = PlaybackLocalFileIdentity(at: fileURL)
        guard currentItemSourceIdentity?.assetURL.standardizedFileURL != fileURL.standardizedFileURL
            || currentItemLocalFileIdentity != fileIdentity
        else {
            return false
        }

        episode.audioURL = fileURL
        snapshot.currentEpisode = episode
        playbackFailureRecoveryPolicy.reset()
        playbackAdSkipPolicy.setZones([])
        snapshot.skipZones = []
        lastAutoSkipEvent = nil
        pendingAutoSkipTarget = nil
        guard rebuildCurrentItem() else {
            return false
        }

        continueOnRebuiltItem()
        recordDiagnosticsEvent("switched to downloaded audio at \(diagnosticsTime(snapshot.position))")
        refreshSmartSpeed()
        return true
    }

    /// Keeps the listening session going across an item rebuild: playback
    /// that was requested resumes, and a paused episode stays paused.
    private func continueOnRebuiltItem() {
        if isPlaybackRequested {
            if isAudioSessionActive {
                requestPlaybackForCurrentItem()
            } else {
                beginAudioSessionActivation()
            }
        } else {
            snapshot.state = .paused
            publishPlaybackState()
        }
    }

    public func setVoiceBoostEnabled(_ isEnabled: Bool) {
        var configuration = voiceBoostConfiguration
        configuration.isEnabled = isEnabled
        updateVoiceBoostConfiguration(configuration)
    }

    public func setSkipIntervals(backward: TimeInterval, forward: TimeInterval) {
        guard backward.isFinite, backward > 0, forward.isFinite, forward > 0 else {
            return
        }

        skipBackwardInterval = backward
        skipForwardInterval = forward
        mediaSession.setSkipIntervals(backward: backward, forward: forward)
    }

    public func setSkipZones(_ zones: [PlaybackSkipZone]) {
        playbackAdSkipPolicy.setZones(zones)
        snapshot.skipZones = playbackAdSkipPolicy.zones
        syncObservableState()
        refreshSkipZoneBoundaryObservers()

        guard snapshot.currentEpisode != nil else {
            return
        }

        let cause: PlaybackAdSkipPolicy.EvaluationCause = if snapshot.position == 0 {
            .playStart
        } else {
            .seekLanding(.restore)
        }
        evaluateAutoSkip(
            previousPosition: snapshot.position == 0 ? -Double.ulpOfOne : nil,
            position: snapshot.position,
            cause: cause
        )
    }

    /// Smart Speed plays a copy of the downloaded file with long pauses cut
    /// short, at the listener's own rate. Streams play unchanged.
    public func setSmartSpeedEnabled(_ isEnabled: Bool) {
        guard isSmartSpeedEnabled != isEnabled else {
            return
        }

        isSmartSpeedEnabled = isEnabled
        refreshSmartSpeed()
    }

    /// Puts the trimmed copy of the current download in the player while
    /// Smart Speed is on, and the file itself otherwise. With saved pauses
    /// the copy is ready before playback starts; without them, analysis
    /// decodes the whole file and the episode plays untrimmed until then.
    private func refreshSmartSpeed() {
        smartSpeedTask?.cancel()
        smartSpeedTask = nil
        removeSmartSpeedSwapObserver()
        stopAwaitingSmartSpeedItem()
        guard snapshot.currentEpisode != nil, let sourceURL = currentItemSourceURL else {
            return
        }
        guard isSmartSpeedEnabled, sourceURL.isFileURL else {
            if currentSmartSpeedItem != nil {
                swapCurrentItemForSmartSpeed()
            }
            return
        }
        guard currentSmartSpeedItem == nil else {
            return
        }
        let fileIdentity = currentItemLocalFileIdentity
        if let smartSpeedSource, smartSpeedSource.matches(sourceURL, fileIdentity) {
            scheduleSmartSpeedSwap(to: smartSpeedSource.composition)
            return
        }

        isAwaitingSmartSpeedItem = SmartSpeedPauseFile.exists(for: sourceURL)
        smartSpeedTask = Task { [weak self] in
            let composition: SmartSpeedCompositionBuilder.Result
            do {
                let analysis: SmartSpeedAnalysis
                if let saved = await SmartSpeedPauseFile.loadInBackground(for: sourceURL) {
                    analysis = saved
                } else {
                    try Task.checkCancellation()
                    self?.stopAwaitingSmartSpeedItem()
                    analysis = try await SmartSpeedPauseFile.analyzeAndSaveInBackground(for: sourceURL)
                }
                composition = try await SmartSpeedCompositionBuilder.build(url: sourceURL, analysis: analysis)
            } catch {
                if !(error is CancellationError), !Task.isCancelled {
                    self?.recordDiagnosticsEvent("smart speed analysis failed: \(error.localizedDescription)")
                    self?.stopAwaitingSmartSpeedItem()
                }
                return
            }
            guard let self,
                  !Task.isCancelled,
                  isSmartSpeedEnabled,
                  currentItemSourceURL == sourceURL,
                  currentItemLocalFileIdentity == fileIdentity
            else {
                return
            }

            smartSpeedTask = nil
            isAwaitingSmartSpeedItem = false
            smartSpeedSource = SmartSpeedSource(url: sourceURL, fileIdentity: fileIdentity, composition: composition)
            scheduleSmartSpeedSwap(to: composition)
        }
    }

    /// While the file plays, waits for the start of the next cut and
    /// resumes the trimmed copy where that cut ends. The reload gap then
    /// falls in a pause that was about to be shortened anyway. Otherwise
    /// nothing is audible, so the swap happens now.
    private func scheduleSmartSpeedSwap(to composition: SmartSpeedCompositionBuilder.Result) {
        removeSmartSpeedSwapObserver()
        let position = player.currentTime().seconds
        guard snapshot.state == .playing,
              let playerItem = player.currentItem,
              position.isFinite,
              let cut = composition.timeline.nextCut(after: position + Self.smartSpeedSwapLeadTime)
        else {
            swapCurrentItemForSmartSpeed()
            return
        }

        let generation = currentItemObservationGeneration
        smartSpeedSwapObserver = PlayerTimeObserver(token: player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: CMTime(seconds: cut.start, preferredTimescale: 600))],
            queue: .main
        ) { [weak self] in
            // Main queue: hop-free, so the swap starts on the cut.
            MainActor.assumeIsolated {
                guard let self,
                      self.smartSpeedSwapObserver != nil,
                      self.isCurrentItemCallback(playerItem, generation: generation)
                else {
                    return
                }
                self.removeSmartSpeedSwapObserver()
                self.swapCurrentItemForSmartSpeed(resumingAt: cut.end)
            }
        })
        recordDiagnosticsEvent("smart speed swap waits for cut at \(diagnosticsTime(cut.start))")
    }

    /// A seek or pause already breaks the audio, so a swap still waiting
    /// for its cut happens then.
    private func performPendingSmartSpeedSwap() {
        guard smartSpeedSwapObserver != nil else {
            return
        }

        removeSmartSpeedSwapObserver()
        swapCurrentItemForSmartSpeed()
    }

    private func removeSmartSpeedSwapObserver() {
        if let smartSpeedSwapObserver {
            player.removeTimeObserver(smartSpeedSwapObserver.token)
            self.smartSpeedSwapObserver = nil
        }
    }

    /// Starts any playback that was held for the trimmed copy on the item
    /// already in the player.
    private func stopAwaitingSmartSpeedItem() {
        guard isAwaitingSmartSpeedItem else {
            return
        }

        isAwaitingSmartSpeedItem = false
        if isPlaybackRequested, isAudioSessionActive {
            requestPlaybackForCurrentItem()
        }
    }

    /// Rebuilds the item, which picks the trimmed copy or the file to match
    /// the setting, at the listener's place on the episode clock.
    private func swapCurrentItemForSmartSpeed(resumingAt resumePosition: TimeInterval? = nil) {
        if let resumePosition {
            snapshot.position = clampedPosition(resumePosition)
        } else if player.currentItem?.status == .readyToPlay,
           playbackPositionProtection.position == nil,
           pendingAutoSkipTarget == nil,
           !hasFinishedCurrentEpisode
        {
            // The 1 Hz tick can trail the player by a second; resume where
            // the listener actually is unless a seek has yet to land.
            let playerPosition = episodeTime(fromPlayer: player.currentTime().seconds)
            if playerPosition.isFinite {
                snapshot.position = clampedPosition(playerPosition)
            }
        }

        let keepsPlaying = isPlaybackRequested && snapshot.state == .playing
        isSwappingSmartSpeedItem = keepsPlaying
        smartSpeedSwapStartedAt = keepsPlaying ? .now : nil
        guard rebuildCurrentItem(showsLoading: !keepsPlaying) else {
            return
        }

        continueOnRebuiltItem()
        if let currentSmartSpeedItem {
            recordDiagnosticsEvent(
                "smart speed trimmed \(diagnosticsTime(currentSmartSpeedItem.timeline.timeSaved)) in \(currentSmartSpeedItem.timeline.segments.count - 1) cuts"
            )
        } else {
            recordDiagnosticsEvent("smart speed off")
        }
    }

    /// While Smart Speed plays, AVPlayer runs on the shortened clock. The
    /// rest of the controller, and everything it publishes, stays on the
    /// episode's own clock, so every player time crosses one of these.
    private func episodeTime(fromPlayer seconds: TimeInterval) -> TimeInterval {
        guard let timeline = currentSmartSpeedItem?.timeline, seconds.isFinite else {
            return seconds
        }
        return timeline.originalTime(forComposition: seconds)
    }

    private func playerTime(fromEpisode seconds: TimeInterval) -> TimeInterval {
        guard let timeline = currentSmartSpeedItem?.timeline, seconds.isFinite else {
            return seconds
        }
        return timeline.compositionTime(forOriginal: seconds)
    }

    public func setAutoSkipEnabled(_ isEnabled: Bool) {
        playbackAdSkipPolicy.setEnabled(isEnabled)
        guard isEnabled, snapshot.currentEpisode != nil else {
            return
        }

        evaluateAutoSkip(
            previousPosition: nil,
            position: snapshot.position,
            cause: .seekLanding(.restore)
        )
    }

    public func setPlaybackDiagnosticsEnabled(_ isEnabled: Bool) {
        guard isPlaybackDiagnosticsEnabled != isEnabled else {
            return
        }

        isPlaybackDiagnosticsEnabled = isEnabled
        if isEnabled {
            refreshPlaybackDiagnosticsText()
        } else if !playbackDiagnosticsText.isEmpty {
            playbackDiagnosticsText = ""
        }
    }

    public func setEventLogHandler(_ handler: (@MainActor (String) -> Void)?) {
        eventLogHandler = handler
    }

    public func play() {
        play(source: "api")
    }

    private func play(source: String) {
        guard snapshot.currentEpisode != nil else {
            return
        }

        let duration = resolvedDuration()
        if hasFinishedCurrentEpisode
            || (duration.map { snapshot.position >= $0 - 0.25 } ?? false)
        {
            let replayPosition = episodeBoundaries.replayPosition(duration: duration)
            currentVoiceBoostTap?.reset()
            // A replay is a programmatic reposition, not a user scrub: the
            // .restore landing intent keeps a pre-roll skip zone armed so it
            // auto-skips instead of being disarmed by the seek.
            seekPlayer(to: replayPosition, mode: .restoredPosition)
            snapshot.position = replayPosition
            hasFinishedCurrentEpisode = false
            markProgressBoundary()
        }

        if !isPlaybackRequested {
            playbackFailureRecoveryPolicy.reset()
        }
        recordDiagnosticsEvent("play requested source=\(source)")
        isPlaybackRequested = true
        isSwappingSmartSpeedItem = false
        if needsCurrentItemRebuildForPlaybackRetry,
           !rebuildCurrentItem()
        {
            return
        }

        rearmExpiredSleepTimerIfNeeded(now: .now)

        guard !isAudioSessionActive else {
            requestPlaybackForCurrentItem()
            return
        }

        beginAudioSessionActivation()
    }

    public func pause() {
        pause(reason: "api")
    }

    private func pause(reason: String) {
        isPlaybackRequested = false
        shouldResumeAfterInterruption = false
        player.pause()
        snapshot.state = snapshot.currentEpisode == nil ? .idle : .paused
        markProgressBoundary()
        recordDiagnosticsEvent("paused reason=\(reason) at \(diagnosticsTime(snapshot.position))")
        publishPlaybackState()
        performPendingSmartSpeedSwap()
    }

    public func unload() {
        if snapshot.currentEpisode != nil {
            markProgressBoundary()
        }
        isPlaybackRequested = false
        shouldResumeAfterInterruption = false
        invalidateAudioSessionActivation()
        removeCurrentItemObservations()
        voiceBoostTrackLoadTask?.cancel()
        voiceBoostTrackLoadTask = nil
        clearSleepTimer()
        clearExpiredSleepTimerRearm()
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentItemGeneration += 1
        currentVoiceBoostTap = nil
        currentLevelMeter = nil
        pendingVoiceBoostContinuationState = nil
        currentItemLocalFileIdentity = nil
        currentItemSourceURL = nil
        smartSpeedTask?.cancel()
        smartSpeedTask = nil
        isAwaitingSmartSpeedItem = false
        currentSmartSpeedItem = nil
        playbackPositionProtection.clear()
        playbackAdSkipPolicy.setZones([])
        autoSkipEventSequence = 0
        lastAutoSkipEvent = nil
        pendingAutoSkipTarget = nil
        episodeBoundaries = .disabled
        hasFinishedCurrentEpisode = false
        recordDiagnosticsEvent("unloaded playback")
        replaceSnapshot(PlaybackSnapshot(rate: snapshot.rate, progressBoundaryID: snapshot.progressBoundaryID))
        mediaSession.clear()
        deactivateAudioSession()
    }

    public func togglePlayPause() {
        togglePlayPause(source: "api")
    }

    private func togglePlayPause(source: String) {
        recordDiagnosticsEvent("toggle play/pause source=\(source) state=\(snapshot.state.accessibilityDescription)")
        if snapshot.state.showsPauseButton {
            pause(reason: "toggle \(source)")
        } else {
            play(source: "toggle \(source)")
        }
    }

    public func seek(to position: TimeInterval) {
        seek(to: position, intent: .scrub)
    }

    public func seek(to position: TimeInterval, intent: PlaybackSeekIntent) {
        guard snapshot.currentEpisode != nil, position.isFinite else {
            return
        }

        let clamped = clampedPosition(position)
        currentVoiceBoostTap?.reset()
        seekPlayer(to: clamped, mode: .userInitiated(intent))
        snapshot.position = clamped
        hasFinishedCurrentEpisode = false
        markProgressBoundary()
        recordDiagnosticsEvent("seek requested position=\(diagnosticsTime(clamped)) intent=\(intent)")
        publishPlaybackState()
    }

    public func skip(by interval: TimeInterval) {
        seek(to: snapshot.position + interval, intent: .skipButton)
    }

    public func setRate(_ rate: Float) {
        snapshot.rate = clampedPlaybackRate(rate)
        if isPlaybackRequested, isAudioSessionActive {
            player.rate = snapshot.rate
        }
        publishPlaybackState()
    }

    public func setRemotePlaybackRateChangeHandler(
        _ handler: PlaybackRateChangeRequestHandler?
    ) {
        remotePlaybackRateChangeHandler = handler
    }

    public func setEpisodeFinishedHandler(_ handler: PlaybackEpisodeFinishedHandler?) {
        episodeFinishedHandler = handler
    }

    public func sleepTimerRemaining(at date: Date = .now) -> TimeInterval? {
        switch sleepTimerMode {
        case .off:
            nil
        case .duration:
            snapshot.sleepTimerEndsAt.map { max(0, $0.timeIntervalSince(date)) }
        case .endOfEpisode:
            PlaybackEndOfEpisodeSleepTimer.remainingPlaybackDuration(
                endPosition: episodeBoundaries.automaticEndPosition(duration: resolvedDuration()),
                position: snapshot.position,
                rate: snapshot.rate
            )
        }
    }

    public func setSleepTimer(duration: TimeInterval?) {
        setSleepTimer(mode: duration.map(PlaybackSleepTimerMode.duration) ?? .off)
    }

    public func setSleepTimer(mode: PlaybackSleepTimerMode) {
        setSleepTimer(mode: mode, now: .now)
    }

    func setSleepTimer(mode: PlaybackSleepTimerMode, now: Date) {
        clearExpiredSleepTimerRearm()
        sleepTimerTask?.cancel()

        switch mode {
        case .off:
            sleepTimerMode = .off
            snapshot.sleepTimerEndsAt = nil
            syncObservableState()
        case .duration(let duration):
            guard duration > 0 else {
                sleepTimerMode = .off
                snapshot.sleepTimerEndsAt = nil
                syncObservableState()
                return
            }
            sleepTimerMode = .duration(duration)
            scheduleSleepTimer(after: duration, now: now)
        case .endOfEpisode:
            guard snapshot.currentEpisode != nil else {
                sleepTimerMode = .off
                snapshot.sleepTimerEndsAt = nil
                syncObservableState()
                return
            }
            sleepTimerMode = .endOfEpisode
            snapshot.sleepTimerEndsAt = nil
            syncObservableState()
        }
    }

    public func extendSleepTimer(by interval: TimeInterval) {
        extendSleepTimer(by: interval, now: .now)
    }

    /// Pushes a running fixed-duration timer's deadline out by `interval`,
    /// measured from what is left at `now`. Off and end-of-episode timers
    /// have no deadline to extend.
    func extendSleepTimer(by interval: TimeInterval, now: Date) {
        guard case .duration = sleepTimerMode,
              let endsAt = snapshot.sleepTimerEndsAt
        else {
            return
        }

        let remaining = max(0, endsAt.timeIntervalSince(now))
        setSleepTimer(mode: .duration(remaining + interval), now: now)
    }

    private func scheduleSleepTimer(after duration: TimeInterval, now: Date) {
        let endsAt = now.addingTimeInterval(duration)
        snapshot.sleepTimerEndsAt = endsAt
        syncObservableState()
        sleepTimerTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(duration))
            } catch {
                return
            }

            guard let self else {
                return
            }

            self.pause(reason: "sleep timer")
            self.clearSleepTimer()
            self.rememberExpiredSleepTimer(mode: .duration(duration), now: .now)
        }
    }

    private func installPeriodicTimeObserver(
        for playerItem: AVPlayerItem,
        generation: Int
    ) {
        timeObserver = PlayerTimeObserver(token: player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let observedPosition = time.seconds
            let observedDuration = playerItem.duration.seconds
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                guard isCurrentItemCallback(playerItem, generation: generation) else {
                    return
                }

                recordLevelWindows()
                handleObservedPlaybackPosition(
                    episodeTime(fromPlayer: observedPosition),
                    duration: episodeTime(fromPlayer: observedDuration),
                    observationGeneration: generation
                )
            }
        })
    }

    func handleObservedPlaybackPosition(
        _ observedPosition: TimeInterval,
        duration observedDuration: TimeInterval?
    ) {
        handleObservedPlaybackPosition(
            observedPosition,
            duration: observedDuration,
            observationGeneration: currentItemObservationGeneration
        )
    }

    func handleObservedPlaybackPosition(
        _ observedPosition: TimeInterval,
        duration observedDuration: TimeInterval?,
        observationGeneration: Int
    ) {
        guard observationGeneration == currentItemObservationGeneration,
              snapshot.currentEpisode != nil
        else {
            return
        }
        guard !hasFinishedCurrentEpisode else {
            return
        }

        let previousPosition = snapshot.position
        let durationChanged = updateDuration(from: observedDuration)
        let newPosition = clampPlaybackPosition(observedPosition, to: resolvedDuration())
        guard shouldAcceptObservedPosition(newPosition) else {
            if durationChanged {
                publishPlaybackState()
            }
            return
        }

        let positionChanged = snapshot.position != newPosition
        if positionChanged {
            snapshot.position = newPosition
        }

        if completeAtOutroIfNeeded(
            previousPosition: previousPosition,
            position: newPosition
        ) {
            return
        }

        if evaluateAutoSkip(
            previousPosition: previousPosition,
            position: newPosition,
            cause: .acceptedTick
        ) {
            return
        }

        guard durationChanged || positionChanged else {
            return
        }

        // Trimmed playback outpaces the rate Now Playing extrapolates with,
        // so its elapsed time is re-anchored on every tick.
        if durationChanged || currentSmartSpeedItem != nil {
            publishPlaybackState()
        } else {
            syncObservableState()
        }
    }

    /// Display-cadence media-time samples for one consumer, independent of the
    /// 1 Hz snapshot publication. Each call installs its own periodic observer,
    /// removed when the consuming task ends, so `.task(id:)` is the intended
    /// lifecycle. Samples read the player directly and never mutate `snapshot`.
    public func mediaClockSamples(
        interval: TimeInterval = 1.0 / 30.0
    ) -> AsyncStream<PlaybackMediaClockSample> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: PlaybackMediaClockSample.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        mediaClockContinuations[id] = continuation
        mediaClockIntervals[id] = interval
        addMediaClockObserver(id)
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.removeMediaClockClient(id)
            }
        }
        // Prime so a consumer that subscribes while paused renders immediately
        // instead of waiting for playback to produce the first callback.
        if let sample = currentMediaClockSample() {
            continuation.yield(sample)
        }
        return stream
    }

    private func addMediaClockObserver(_ id: UUID) {
        guard let interval = mediaClockIntervals[id],
              let continuation = mediaClockContinuations[id]
        else {
            return
        }

        mediaClockObservers[id] = PlayerTimeObserver(token: player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: interval, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            // AVPlayer invokes this callback on the explicitly supplied main
            // queue, so avoid allocating a MainActor hop at display cadence.
            MainActor.assumeIsolated {
                guard let self, let sample = self.currentMediaClockSample() else {
                    return
                }
                continuation.yield(sample)
            }
        })
    }

    var mediaClockClientCount: Int {
        mediaClockObservers.count
    }

    public var currentItemSourceIdentity: PlaybackItemSourceIdentity? {
        guard let item = player.currentItem, let assetURL = currentItemSourceURL else {
            return nil
        }

        let kind: PlaybackItemSourceIdentity.Kind = if assetURL.isFileURL {
            .localFile
        } else {
            .networkStream
        }
        let itemDuration = episodeTime(fromPlayer: item.duration.seconds)
        return PlaybackItemSourceIdentity(
            assetURL: assetURL,
            kind: kind,
            itemDuration: itemDuration.isFinite && itemDuration > 0 ? itemDuration : nil
        )
    }

    private func currentMediaClockSample() -> PlaybackMediaClockSample? {
        let seconds = episodeTime(fromPlayer: player.currentTime().seconds)
        guard seconds.isFinite else {
            return nil
        }
        return PlaybackMediaClockSample(
            position: seconds,
            rate: player.rate,
            isPlaying: player.timeControlStatus == .playing
        )
    }

    private func removeMediaClockClient(_ id: UUID) {
        if let observer = mediaClockObservers.removeValue(forKey: id) {
            player.removeTimeObserver(observer.token)
        }
        mediaClockIntervals.removeValue(forKey: id)
        mediaClockContinuations.removeValue(forKey: id)?.finish()
    }

    private func configurePlayer() {
        // Audio-only app: external playback hands the stream to a video-capable
        // AirPlay receiver (Mac, Apple TV), which opens a video surface and
        // bypasses the Voice Boost tap. Keep AirPlay on the audio route instead.
        player.allowsExternalPlayback = false
        observePlayerTimeControlStatus()
    }

    /// After a media services reset the old AVPlayer never plays again, and
    /// Apple requires recreating AVFoundation objects. Callers rebuild the
    /// current item on the new player.
    private func replacePlayer() {
        removeCurrentItemObservations()
        for observer in mediaClockObservers.values {
            player.removeTimeObserver(observer.token)
        }
        mediaClockObservers.removeAll()
        playerTimeControlStatusObservation?.invalidate()
        playerTimeControlStatusObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)

        player = AVPlayer()
        configurePlayer()
        for id in mediaClockContinuations.keys {
            addMediaClockObserver(id)
        }
        recordDiagnosticsEvent("replaced player")
    }

    var playerIdentityForTesting: ObjectIdentifier {
        ObjectIdentifier(player)
    }

    private func observePlayerTimeControlStatus() {
        playerTimeControlStatusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handlePlayerTimeControlStatusChanged()
            }
        }
    }

    private func installRemoteCommands() {
        mediaSession.install(RemoteCommandHandlers(
            play: { [weak self] in
                self?.play(source: "remote play command")
            },
            pause: { [weak self] in
                self?.pause(reason: "remote pause command")
            },
            togglePlayPause: { [weak self] in
                self?.togglePlayPause(source: "remote toggle command")
            },
            skipForward: { [weak self] in
                self?.skipForward()
            },
            skipBackward: { [weak self] in
                self?.skipBackward()
            },
            seek: { [weak self] position in
                self?.seek(to: position, intent: .scrub)
            },
            changeRate: { [weak self] rate in
                self?.handleRemotePlaybackRateChange(rate)
            }
        ))
    }

    private func skipForward() {
        skip(by: skipForwardInterval)
    }

    private func skipBackward() {
        skip(by: -skipBackwardInterval)
    }

    func handleRemotePlaybackRateChange(_ rate: Float) {
        if let remotePlaybackRateChangeHandler {
            remotePlaybackRateChangeHandler(rate)
        } else {
            setRate(rate)
        }
    }

    private func installAudioSessionObservers() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        audioSessionInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleAudioSessionInterruption(rawType: rawType, rawOptions: rawOptions)
            }
        }

        audioSessionRouteChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let previousRoute = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey]
                as? AVAudioSessionRouteDescription
            let previousOutputs = previousRoute?.outputs.map(\.portType.rawValue) ?? []
            Task { @MainActor [weak self] in
                let currentOutputs = await Self.currentAudioRouteOutputs()
                self?.handleAudioSessionRouteChange(
                    rawReason: rawReason,
                    previousOutputs: previousOutputs,
                    currentOutputs: currentOutputs
                )
            }
        }

        audioSessionSecondaryAudioObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.silenceSecondaryAudioHintNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt
            Task { @MainActor [weak self] in
                let type = rawType.flatMap(AVAudioSession.SilenceSecondaryAudioHintType.init(rawValue:))
                self?.recordDiagnosticsEvent("secondary audio hint \(type == .begin ? "begin" : type == .end ? "end" : "unknown")")
            }
        }

        audioSessionOutputVolumeObservation = AVAudioSession.sharedInstance().observe(
            \.outputVolume,
            options: [.old, .new]
        ) { [weak self] _, change in
            let old = change.oldValue ?? -1
            let new = change.newValue ?? -1
            Task { @MainActor [weak self] in
                self?.recordDiagnosticsEvent("system output volume \(String(format: "%.2f", old)) -> \(String(format: "%.2f", new))")
            }
        }

        audioSessionMediaServicesResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAudioSessionMediaServicesWereReset()
            }
        }
        #endif
    }

    private func removeAudioSessionObservers() {
        if let audioSessionInterruptionObserver {
            NotificationCenter.default.removeObserver(audioSessionInterruptionObserver)
            self.audioSessionInterruptionObserver = nil
        }
        if let audioSessionRouteChangeObserver {
            NotificationCenter.default.removeObserver(audioSessionRouteChangeObserver)
            self.audioSessionRouteChangeObserver = nil
        }
        if let audioSessionMediaServicesResetObserver {
            NotificationCenter.default.removeObserver(audioSessionMediaServicesResetObserver)
            self.audioSessionMediaServicesResetObserver = nil
        }
        if let audioSessionSecondaryAudioObserver {
            NotificationCenter.default.removeObserver(audioSessionSecondaryAudioObserver)
            self.audioSessionSecondaryAudioObserver = nil
        }
        audioSessionOutputVolumeObservation?.invalidate()
        audioSessionOutputVolumeObservation = nil
    }

    private func handleAudioSessionInterruption(rawType: UInt?, rawOptions: UInt?) {
        #if os(iOS) || os(tvOS) || os(visionOS)
        guard let rawType,
              let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else {
            return
        }

        switch type {
        case .began:
            handleAudioSessionInterruptionBegan()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions ?? 0)
            handleAudioSessionInterruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            break
        }
        #endif
    }

    func handleAudioSessionMediaServicesWereReset() {
        invalidateAudioSessionActivation()
        isAudioSessionActive = false
        recordDiagnosticsEvent("audio session media services reset")
        replacePlayer()

        guard snapshot.currentEpisode != nil, rebuildCurrentItem() else {
            return
        }

        continueOnRebuiltItem()
    }

    func handleAudioSessionInterruptionBegan() {
        let recordedResumeIntent = PlaybackInterruptionResumePolicy.shouldRecordResumeIntent(
            isPlaybackRequested: isPlaybackRequested,
            state: snapshot.state
        )
        invalidateAudioSessionActivation()
        isAudioSessionActive = false
        guard snapshot.currentEpisode != nil else {
            isPlaybackRequested = false
            player.pause()
            shouldResumeAfterInterruption = false
            return
        }
        pause(reason: "audio session interruption began")
        shouldResumeAfterInterruption = recordedResumeIntent
    }

    func handleAudioSessionInterruptionEnded(shouldResume: Bool) {
        defer {
            shouldResumeAfterInterruption = false
        }

        guard PlaybackInterruptionResumePolicy.shouldResume(
            operatingSystemShouldResume: shouldResume,
            recordedResumeIntent: shouldResumeAfterInterruption,
            hasCurrentEpisode: snapshot.currentEpisode != nil
        ) else {
            return
        }

        play(source: "audio session interruption ended")
    }

    #if os(iOS) || os(tvOS) || os(visionOS)
    /// Port types only (`AirPlay`, `BluetoothA2DP`, `Speaker`): port names are
    /// the user's device names and the event log persists on disk.
    @concurrent
    private static func currentAudioRouteOutputs() async -> [String] {
        AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType.rawValue)
    }
    #endif

    private func handleAudioSessionRouteChange(
        rawReason: UInt?,
        previousOutputs: [String],
        currentOutputs: [String]
    ) {
        #if os(iOS) || os(tvOS) || os(visionOS)
        guard let rawReason,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
        else {
            return
        }

        recordDiagnosticsEvent(
            "audio route changed reason=\(AVFoundationPlaybackDiagnosticsFormatter.routeChangeReason(reason)) from=\(previousOutputs.joined(separator: ",")) to=\(currentOutputs.joined(separator: ",")) externalPlayback=\(player.isExternalPlaybackActive)"
        )

        switch reason {
        case .oldDeviceUnavailable:
            handleAudioSessionOldDeviceUnavailable()
        default:
            break
        }
        #endif
    }

    func handleAudioSessionOldDeviceUnavailable() {
        guard snapshot.currentEpisode != nil else {
            return
        }

        if case .failed = snapshot.state {
            shouldResumeAfterInterruption = false
            recordDiagnosticsEvent("old audio route unavailable while playback failed")
            return
        }

        pause(reason: "old audio route unavailable")
    }

    private func makePlayerItem(
        audioURL: URL,
        continuationState: VoiceBoostContinuationState? = nil
    ) -> AVPlayerItem {
        currentItemLocalFileIdentity = PlaybackLocalFileIdentity(at: audioURL)
        currentItemSourceURL = audioURL
        if isSmartSpeedEnabled,
           let smartSpeedSource,
           smartSpeedSource.matches(audioURL, currentItemLocalFileIdentity)
        {
            currentSmartSpeedItem = smartSpeedSource.composition
            let playerItem = AVPlayerItem(asset: smartSpeedSource.composition.composition)
            // The composition's track is known up front, so the tap binds
            // to it here with the cut fades rather than after a track load.
            installVoiceBoostTap(on: playerItem, continuationState: continuationState)
            return playerItem
        }

        currentSmartSpeedItem = nil
        // Local files get a precise timeline: karaoke equates item media time
        // with transcript timestamps, and estimated MP3 timing (the default)
        // can report a duration and land seeks at bytes that do not
        // correspond to the requested time in stitched or VBR files.
        let options: [String: Any]? = audioURL.isFileURL
            ? [AVURLAssetPreferPreciseDurationAndTimingKey: true]
            : nil
        let asset = AVURLAsset(url: audioURL, options: options)
        let playerItem = AVPlayerItem(asset: asset)
        installVoiceBoostTap(on: playerItem, continuationState: continuationState)
        scheduleTrackBoundVoiceBoostTapInstall(for: playerItem, asset: asset)
        return playerItem
    }

    private func scheduleTrackBoundVoiceBoostTapInstall(for playerItem: AVPlayerItem, asset: AVURLAsset) {
        voiceBoostTrackLoadTask?.cancel()
        guard voiceBoostConfiguration.isEnabled else {
            voiceBoostTrackLoadTask = nil
            return
        }

        voiceBoostTrackLoadTask = Task { @MainActor [weak self, weak playerItem] in
            do {
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                // Track loading can resume after item/configuration changes; keep these guards beside the install.
                guard !Task.isCancelled,
                      let self,
                      let playerItem,
                      self.player.currentItem === playerItem,
                      voiceBoostConfiguration.isEnabled,
                      let audioTrack = audioTracks.first
                else {
                    return
                }

                installVoiceBoostTap(on: playerItem, audioTrack: audioTrack)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self?.voiceBoostTapDiagnostics?.recordTapInstallFailure(error)
            }
        }
    }

    private func installVoiceBoostTap(
        on playerItem: AVPlayerItem,
        audioTrack: AVAssetTrack? = nil,
        continuationState: VoiceBoostContinuationState? = nil
    ) {
        // A fresh load passes neither state nor track. A same-session rebuild
        // and its later track binding must both retain the measurement history.
        let carriedState = continuationState ?? (audioTrack != nil
            ? currentVoiceBoostTap?.captureContinuationState() : nil)
        currentVoiceBoostTap = nil
        currentLevelMeter = nil
        pendingVoiceBoostContinuationState = nil
        guard voiceBoostConfiguration.isEnabled else {
            // Retain adaptation without installing a disabled tap: a local
            // handoff must not introduce audio callbacks while Voice Boost is off.
            pendingVoiceBoostContinuationState = carriedState
            playerItem.audioMix = currentSmartSpeedItem.map(levelMeteredAudioMix)
            return
        }

        do {
            voiceBoostTapDiagnostics?.recordTapInstallAttempt()
            let tap = try voiceBoostAudioTapFactory(voiceBoostConfiguration, voiceBoostTapDiagnostics)
            voiceBoostTapDiagnostics?.recordTapInstallSuccess()
            if let carriedState {
                tap.seedContinuationState(carriedState)
            }
            let inputParameters = if let audioTrack {
                AVMutableAudioMixInputParameters(track: audioTrack)
            } else if let currentSmartSpeedItem {
                currentSmartSpeedItem.makeInputParameters()
            } else {
                AVMutableAudioMixInputParameters()
            }
            inputParameters.audioTapProcessor = tap.audioTapProcessor

            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = [inputParameters]
            playerItem.audioMix = audioMix
            currentVoiceBoostTap = tap
            recordDiagnosticsEvent(
                "voice boost installed history=\(carriedState?.integratedBlockCount ?? 0) gain=\(carriedState?.controlSnapshot.currentAutoGainDB ?? 0) trackBound=\(audioTrack != nil) enabled=\(voiceBoostConfiguration.isEnabled)"
            )
        } catch {
            if case VoiceBoostAudioTapError.creationFailed(let status) = error {
                voiceBoostTapDiagnostics?.recordTapCreationFailure(status: status)
            } else {
                voiceBoostTapDiagnostics?.recordTapCreationFailure(status: nil)
            }
            playerItem.audioMix = nil
            currentVoiceBoostTap = nil
        }
    }

    /// A read-only level meter on the Smart Speed item, so the event log
    /// shows whether the app's own output drops.
    private func levelMeteredAudioMix(for item: SmartSpeedCompositionBuilder.Result) -> AVMutableAudioMix {
        let parameters = item.makeInputParameters()
        if let meter = PlaybackLevelMeterTap() {
            parameters.audioTapProcessor = meter.audioTapProcessor
            currentLevelMeter = meter
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [parameters]
        return audioMix
    }

    private func recordLevelWindows() {
        guard let currentLevelMeter else {
            return
        }
        for window in currentLevelMeter.drainWindows() {
            recordDiagnosticsEvent(
                "level from=\(diagnosticsTime(episodeTime(fromPlayer: window.start))) to=\(diagnosticsTime(episodeTime(fromPlayer: window.end))) rms=\(String(format: "%.1f", window.rmsDB))dB peak=\(String(format: "%.1f", window.peakDB))dB rate=\(player.rate)"
            )
        }
    }

    private func observeCurrentItem(_ playerItem: AVPlayerItem) {
        currentItemGeneration += 1
        let generation = currentItemObservationGeneration
        installPeriodicTimeObserver(for: playerItem, generation: generation)
        observeEnd(of: playerItem, generation: generation)
        observePlaybackStall(of: playerItem, generation: generation)
        observeDuration(of: playerItem, generation: generation)
        observeStatus(of: playerItem, generation: generation)
        observeBuffering(of: playerItem, generation: generation)
        refreshSkipZoneBoundaryObservers()
    }

    private func observeEnd(of playerItem: AVPlayerItem, generation: Int) {
        currentItemEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      isCurrentItemCallback(playerItem, generation: generation)
                else {
                    return
                }
                handleCurrentItemDidPlayToEnd(playerItem)
            }
        }
    }

    private func observePlaybackStall(of playerItem: AVPlayerItem, generation: Int) {
        currentItemPlaybackStalledObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      isCurrentItemCallback(playerItem, generation: generation)
                else {
                    return
                }
                handleCurrentItemPlaybackStalled(playerItem)
            }
        }
    }

    private func observeDuration(of playerItem: AVPlayerItem, generation: Int) {
        currentItemDurationObservation = playerItem.observe(\.duration, options: [.initial, .new]) { [weak self] item, _ in
            let observedDuration = item.duration.seconds
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                guard isCurrentItemCallback(item, generation: generation) else {
                    return
                }
                handleObservedDuration(
                    episodeTime(fromPlayer: observedDuration),
                    observationGeneration: generation
                )
            }
        }
    }

    private func observeStatus(of playerItem: AVPlayerItem, generation: Int) {
        currentItemStatusObservation = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      isCurrentItemCallback(item, generation: generation)
                else {
                    return
                }
                handleCurrentItemStatusChanged(item)
            }
        }
    }

    private func observeBuffering(of playerItem: AVPlayerItem, generation: Int) {
        currentItemLikelyToKeepUpObservation = playerItem.observe(
            \.isPlaybackLikelyToKeepUp,
            options: [.new]
        ) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      isCurrentItemCallback(item, generation: generation)
                else {
                    return
                }
                handleCurrentItemBufferingChanged(item)
            }
        }

        currentItemBufferEmptyObservation = playerItem.observe(
            \.isPlaybackBufferEmpty,
            options: [.new]
        ) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      isCurrentItemCallback(item, generation: generation)
                else {
                    return
                }
                handleCurrentItemBufferingChanged(item)
            }
        }
    }

    private func removeCurrentItemObservations() {
        currentItemObservationGeneration += 1
        if let timeObserver {
            player.removeTimeObserver(timeObserver.token)
            self.timeObserver = nil
        }
        removeOutroBoundaryObserver()
        removeSkipZoneBoundaryObservers()
        removeSmartSpeedSwapObserver()
        if let currentItemEndObserver {
            NotificationCenter.default.removeObserver(currentItemEndObserver)
            self.currentItemEndObserver = nil
        }
        if let currentItemPlaybackStalledObserver {
            NotificationCenter.default.removeObserver(currentItemPlaybackStalledObserver)
            self.currentItemPlaybackStalledObserver = nil
        }
        currentItemDurationObservation?.invalidate()
        currentItemDurationObservation = nil
        currentItemStatusObservation?.invalidate()
        currentItemStatusObservation = nil
        currentItemLikelyToKeepUpObservation?.invalidate()
        currentItemLikelyToKeepUpObservation = nil
        currentItemBufferEmptyObservation?.invalidate()
        currentItemBufferEmptyObservation = nil
    }

    private func handlePlayerTimeControlStatusChanged() {
        guard snapshot.currentEpisode != nil, isPlaybackRequested, isAudioSessionActive else {
            return
        }

        switch player.timeControlStatus {
        case .playing:
            if isSwappingSmartSpeedItem, let smartSpeedSwapStartedAt {
                isSwappingSmartSpeedItem = false
                recordDiagnosticsEvent("smart speed swap resumed after \(smartSpeedSwapStartedAt.duration(to: .now))")
            }
            snapshot.state = .playing
            publishPlaybackState()
        case .waitingToPlayAtSpecifiedRate:
            transitionToBuffering(reason: "player waiting reason=\(player.reasonForWaitingToPlay?.rawValue ?? "nil")")
        case .paused:
            break
        @unknown default:
            break
        }
    }

    private func handleCurrentItemStatusChanged(_ playerItem: AVPlayerItem) {
        guard player.currentItem === playerItem else {
            return
        }

        switch playerItem.status {
        case .unknown:
            if isPlaybackRequested, isAudioSessionActive {
                transitionToBuffering(reason: "item status unknown")
            }
        case .readyToPlay:
            hasReplacedPlayerForFailedItem = false
            if updateDuration(from: episodeTime(fromPlayer: playerItem.duration.seconds)) {
                publishPlaybackState()
            }
            if isPlaybackRequested {
                if isAudioSessionActive {
                    requestPlaybackForReadyItem(playerItem)
                }
            } else if snapshot.state == .loading || snapshot.state == .buffering {
                snapshot.state = .paused
                publishPlaybackState()
            }
        case .failed:
            handleFailedCurrentItem(playerItem)
        @unknown default:
            failPlayback(message: "This episode could not be played.")
        }
    }

    private func handleCurrentItemBufferingChanged(_ playerItem: AVPlayerItem) {
        guard player.currentItem === playerItem,
              playerItem.status == .readyToPlay,
              isPlaybackRequested,
              isAudioSessionActive
        else {
            return
        }

        if playerItem.isPlaybackBufferEmpty {
            transitionToBuffering(reason: "item playback buffer empty")
        } else if playerItem.isPlaybackLikelyToKeepUp {
            requestPlaybackForReadyItem(playerItem)
        }
    }

    private func handleCurrentItemPlaybackStalled(_ playerItem: AVPlayerItem) {
        guard player.currentItem === playerItem, snapshot.currentEpisode != nil else {
            return
        }

        handleCurrentItemPlaybackStalled()
    }

    func handleCurrentItemPlaybackStalled() {
        if isPlaybackRequested {
            recordDiagnosticsEvent("playback stalled at \(diagnosticsTime(snapshot.position))")
            transitionToBuffering(reason: "AVPlayerItemPlaybackStalled")
            resumeUsingAutomaticBufferWaiting()
        }
    }

    var automaticallyWaitsToMinimizeStalling: Bool {
        player.automaticallyWaitsToMinimizeStalling
    }

    private func requestPlaybackForCurrentItem() {
        guard !isAwaitingSmartSpeedItem else {
            transitionToBuffering(reason: "awaiting smart speed item")
            return
        }
        guard let playerItem = player.currentItem else {
            failPlayback(message: "This episode could not be played.")
            return
        }

        switch playerItem.status {
        case .readyToPlay:
            requestPlaybackForReadyItem(playerItem)
        case .failed:
            handleFailedCurrentItem(playerItem)
        case .unknown:
            transitionToBuffering(reason: "request playback for unknown item")
            player.rate = snapshot.rate
        @unknown default:
            failPlayback(message: "This episode could not be played.")
        }
    }

    private func requestPlaybackForReadyItem(_ playerItem: AVPlayerItem) {
        guard player.currentItem === playerItem, snapshot.currentEpisode != nil else {
            return
        }
        guard !isAwaitingSmartSpeedItem else {
            transitionToBuffering(reason: "awaiting smart speed item")
            return
        }

        // This path follows an explicit user request, so immediate start is
        // preferable to AVPlayer extending the tap-to-audio delay.
        playbackStartBehaviorObserver?(.immediateUserRequest)
        player.playImmediately(atRate: snapshot.rate)
        switch player.timeControlStatus {
        case .playing:
            snapshot.state = .playing
        case .waitingToPlayAtSpecifiedRate, .paused:
            snapshot.state = isSwappingSmartSpeedItem ? .playing : .buffering
        @unknown default:
            snapshot.state = isSwappingSmartSpeedItem ? .playing : .buffering
        }
        recordDiagnosticsEvent(
            "requested ready item playback result=\(snapshot.state.accessibilityDescription) timeControlStatus=\(diagnosticsTimeControlStatus) waitingReason=\(player.reasonForWaitingToPlay?.rawValue ?? "nil")"
        )
        publishPlaybackState()
    }

    private func resumeUsingAutomaticBufferWaiting() {
        playbackStartBehaviorObserver?(.automaticBufferWaiting)
        player.defaultRate = snapshot.rate
        player.play()
    }

    private var needsCurrentItemRebuildForPlaybackRetry: Bool {
        guard snapshot.currentEpisode != nil else {
            return false
        }
        if case .failed = snapshot.state {
            return true
        }
        guard let currentItem = player.currentItem else {
            return true
        }

        return currentItem.status == .failed
    }

    private func rebuildCurrentItem(showsLoading: Bool = true) -> Bool {
        guard let episode = snapshot.currentEpisode,
              let audioURL = episode.audioURL
        else {
            failPlayback(message: "This episode could not be played.")
            return false
        }

        removeCurrentItemObservations()
        playbackPositionProtection.clear()
        voiceBoostTrackLoadTask?.cancel()
        voiceBoostTrackLoadTask = nil
        player.pause()
        let continuationState = currentVoiceBoostTap?.captureContinuationState()
            ?? pendingVoiceBoostContinuationState
        currentVoiceBoostTap = nil

        let retryItem = makePlayerItem(audioURL: audioURL, continuationState: continuationState)
        player.replaceCurrentItem(with: retryItem)
        observeCurrentItem(retryItem)
        refreshOutroBoundaryObserver()

        if snapshot.position > 0 {
            seekPlayer(to: snapshot.position, mode: .restoredPosition)
        }

        if showsLoading {
            snapshot.state = .loading
        }
        recordDiagnosticsEvent("rebuilt player item at \(diagnosticsTime(snapshot.position))")
        publishPlaybackState()
        return true
    }

    private func handleFailedCurrentItem(_ playerItem: AVPlayerItem) {
        handleFailedCurrentItem(playerItem, error: playerItem.error)
    }

    func handleCurrentItemFailed(error: (any Error)?) {
        guard let playerItem = player.currentItem else {
            return
        }

        handleFailedCurrentItem(playerItem, error: error)
    }

    private func handleFailedCurrentItem(_ playerItem: AVPlayerItem, error: (any Error)?) {
        if recoverFromFailedCurrentItemIfNeeded(playerItem) {
            return
        }
        if recoverFromMediaServicesResetIfNeeded(error: error) {
            return
        }
        failPlayback(error: error, failedItem: playerItem)
    }

    /// The media server can die under a paused item (seen during a phone
    /// call), and the reset notification may arrive minutes later. Replacing
    /// the player here keeps the episode resumable instead of failed.
    private func recoverFromMediaServicesResetIfNeeded(error: (any Error)?) -> Bool {
        guard PlaybackFailureRecoveryPolicy.isMediaServicesReset(error),
              snapshot.currentEpisode != nil,
              !hasReplacedPlayerForFailedItem
        else {
            return false
        }

        hasReplacedPlayerForFailedItem = true
        recordDiagnosticsEvent("media services reset failed the item at \(diagnosticsTime(snapshot.position))")
        replacePlayer()
        guard rebuildCurrentItem() else {
            return true
        }

        continueOnRebuiltItem()
        return true
    }

    private func transitionToBuffering(reason: String) {
        guard snapshot.currentEpisode != nil, snapshot.state != .buffering else {
            return
        }
        guard !(isSwappingSmartSpeedItem && isPlaybackRequested) else {
            recordDiagnosticsEvent("smart speed swap loading reason=\(reason)")
            return
        }

        snapshot.state = .buffering
        recordDiagnosticsEvent("buffering reason=\(reason)")
        publishPlaybackState()
    }

    private func recoverFromFailedCurrentItemIfNeeded(_ playerItem: AVPlayerItem) -> Bool {
        guard player.currentItem === playerItem,
              snapshot.currentEpisode != nil,
              isPlaybackRequested,
              playbackFailureRecoveryPolicy.shouldAttemptAutomaticRetry(
                error: playerItem.error,
                errorLog: playerItem.errorLog()
              )
        else {
            return false
        }

        recordFailedItemDiagnostics(playerItem, error: playerItem.error, prefix: "transient failure")
        recordDiagnosticsEvent(
            "automatic transient playback retry attempt=\(playbackFailureRecoveryPolicy.automaticTransientFailureRetryCount) at \(diagnosticsTime(snapshot.position))"
        )

        guard rebuildCurrentItem() else {
            return true
        }

        requestPlaybackForCurrentItem()
        return true
    }

    private func failPlayback(error: (any Error)?, failedItem: AVPlayerItem? = nil) {
        recordFailedItemDiagnostics(failedItem, error: error, prefix: "terminal failure")
        let message = error?.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if let message, !message.isEmpty {
            failPlayback(message: "This episode could not be played. \(message)")
        } else {
            failPlayback(message: "This episode could not be played.")
        }
    }

    private func failPlayback(message: String) {
        isPlaybackRequested = false
        shouldResumeAfterInterruption = false
        player.pause()
        let playerPosition = clampPlaybackPosition(
            episodeTime(fromPlayer: player.currentTime().seconds),
            to: resolvedDuration()
        )
        if playerPosition > snapshot.position {
            snapshot.position = playerPosition
        }
        snapshot.state = .failed(message)
        markProgressBoundary()
        recordDiagnosticsEvent("playback failed: \(message)")
        publishPlaybackState()
    }

    private func recordFailedItemDiagnostics(
        _ playerItem: AVPlayerItem?,
        error: (any Error)?,
        prefix: String
    ) {
        recordDiagnosticsEvent("\(prefix) error=\(AVFoundationPlaybackDiagnosticsFormatter.errorSummary(for: error))")
        if let event = playerItem?.errorLog()?.events.last {
            recordDiagnosticsEvent(
                "\(prefix) errorLog=\(AVFoundationPlaybackDiagnosticsFormatter.errorLogSummary(for: event))"
            )
        }
        if let event = playerItem?.accessLog()?.events.last {
            recordDiagnosticsEvent(
                "\(prefix) accessLog=\(AVFoundationPlaybackDiagnosticsFormatter.accessLogSummary(for: event))"
            )
        }
    }

    func handleCurrentItemDidPlayToEnd(_ playerItem: AVPlayerItem) {
        guard player.currentItem === playerItem else {
            return
        }

        handleCurrentItemDidPlayToEnd()
    }

    func handleCurrentItemDidPlayToEnd() {
        guard !hasFinishedCurrentEpisode else {
            return
        }

        finishCurrentEpisode()
    }

    private func completeAtOutroIfNeeded(
        previousPosition: TimeInterval,
        position: TimeInterval
    ) -> Bool {
        guard !hasFinishedCurrentEpisode,
              episodeBoundaries.crossesOutro(
                  from: previousPosition,
                  to: position,
                  duration: resolvedDuration()
              )
        else {
            return false
        }

        finishCurrentEpisode()
        return true
    }

    private func finishCurrentEpisode() {
        let finishedEpisode = snapshot.currentEpisode
        let isEndOfEpisodeSleepTimer = sleepTimerMode == .endOfEpisode
        let completionPolicy: PlaybackCompletionPolicy = isEndOfEpisodeSleepTimer
            ? .stop
            : .advanceIfQueued
        hasFinishedCurrentEpisode = true
        isPlaybackRequested = false
        shouldResumeAfterInterruption = false
        if let duration = resolvedDuration() {
            snapshot.duration = duration
            snapshot.position = duration
        }
        player.pause()
        if isEndOfEpisodeSleepTimer {
            clearSleepTimer()
        }
        snapshot.state = snapshot.currentEpisode == nil ? .idle : .paused
        markProgressBoundary()
        publishPlaybackState()
        if let finishedEpisode {
            episodeFinishedHandler?(finishedEpisode, completionPolicy)
        }
    }

    private func clampedPosition(_ position: TimeInterval) -> TimeInterval {
        clampPlaybackPosition(position, to: resolvedDuration())
    }

    private enum SeekMode {
        case userInitiated(PlaybackSeekIntent)
        case restoredPosition
        case autoSkip

        var intent: PlaybackSeekIntent {
            switch self {
            case .userInitiated(let intent):
                intent
            case .restoredPosition:
                .restore
            case .autoSkip:
                .autoSkip
            }
        }
    }

    private func seekPlayer(to position: TimeInterval, mode: SeekMode = .userInitiated(.scrub)) {
        performPendingSmartSpeedSwap()
        let clamped = clampedPosition(position)
        switch mode {
        case .autoSkip:
            pendingAutoSkipTarget = clamped
        case .userInitiated, .restoredPosition:
            pendingAutoSkipTarget = nil
        }
        let protectedSeekGeneration = playbackPositionProtection.startSeek(to: clamped)
        let itemGeneration = currentItemObservationGeneration
        let time = Self.seekTime(for: playerTime(fromEpisode: clamped), landsExactly: mode.intent.landsExactly)
        let completion: @Sendable (Bool) -> Void = { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, currentItemObservationGeneration == itemGeneration else {
                    return
                }
                completeProtectedSeek(
                    generation: protectedSeekGeneration,
                    finished: finished,
                    position: clamped,
                    intent: mode.intent
                )
            }
        }

        if mode.intent.landsExactly {
            player.seek(
                to: time,
                toleranceBefore: .zero,
                toleranceAfter: .zero,
                completionHandler: completion
            )
        } else {
            player.seek(to: time, completionHandler: completion)
        }
    }

    /// Exact landings round up to the next tick, never down: a chapter start
    /// at 60.002 s would otherwise become 60.0017 s and read as the previous
    /// chapter after an accurate seek. Tolerant seeks keep the nearest tick.
    nonisolated static func seekTime(for seconds: TimeInterval, landsExactly: Bool) -> CMTime {
        let timescale: CMTimeScale = 600
        guard landsExactly else {
            return CMTime(seconds: seconds, preferredTimescale: timescale)
        }
        return CMTime(value: CMTimeValue((seconds * Double(timescale)).rounded(.up)), timescale: timescale)
    }

    private func completeProtectedSeek(
        generation: Int?,
        finished: Bool,
        position: TimeInterval,
        intent: PlaybackSeekIntent
    ) {
        guard let generation else {
            return
        }

        playbackPositionProtection.completeSeek(generation: generation, finished: finished)
        recordDiagnosticsEvent(
            "seek completed target=\(diagnosticsTime(position)) actual=\(diagnosticsTime(episodeTime(fromPlayer: player.currentTime().seconds))) finished=\(finished) intent=\(intent)"
        )
        if finished {
            evaluateAutoSkip(
                previousPosition: nil,
                position: position,
                cause: .seekLanding(intent)
            )
        }
        refreshPlaybackDiagnosticsText()
    }

    @discardableResult
    private func evaluateAutoSkip(
        previousPosition: TimeInterval?,
        position: TimeInterval,
        cause: PlaybackAdSkipPolicy.EvaluationCause
    ) -> Bool {
        guard let command = playbackAdSkipPolicy.evaluate(
            previousPosition: previousPosition,
            position: position,
            duration: resolvedDuration(),
            cause: cause
        ) else {
            return false
        }

        performAutoSkip(command, from: position)
        return true
    }

    private func performAutoSkip(_ command: PlaybackAdSkipPolicy.Command, from position: TimeInterval) {
        guard snapshot.currentEpisode != nil else {
            return
        }

        switch command {
        case .skip(let target, let zoneID):
            currentVoiceBoostTap?.reset()
            autoSkipEventSequence += 1
            lastAutoSkipEvent = PlaybackAutoSkipEvent(zoneID: zoneID, sequence: autoSkipEventSequence)
            if episodeBoundaries.crossesOutro(
                from: position,
                to: target,
                duration: resolvedDuration()
            ), let cutoff = episodeBoundaries.outroCutoff(duration: resolvedDuration())
            {
                recordDiagnosticsEvent(
                    "auto-skip zone=\(zoneID) from=\(diagnosticsTime(position)) reached outro=\(diagnosticsTime(cutoff))"
                )
                finishCurrentEpisode()
                return
            }
            seekPlayer(to: target, mode: .autoSkip)
            snapshot.position = target
            markProgressBoundary()
            recordDiagnosticsEvent(
                "auto-skip zone=\(zoneID) from=\(diagnosticsTime(position)) to=\(diagnosticsTime(target))"
            )
            publishPlaybackState()
        }
    }

    private func shouldAcceptObservedPosition(_ position: TimeInterval) -> Bool {
        if case .failed = snapshot.state {
            return false
        }

        if let pendingAutoSkipTarget {
            guard position + Self.autoSkipSettleTolerance >= pendingAutoSkipTarget else {
                return false
            }
            self.pendingAutoSkipTarget = nil
        }

        return playbackPositionProtection.acceptsObservedPosition(position)
    }

    private func resolvedDuration() -> TimeInterval? {
        snapshot.bestFiniteDuration(preferring: player.currentItem.map { episodeTime(fromPlayer: $0.duration.seconds) })
    }

    @discardableResult
    private func updateDuration(from seconds: TimeInterval?) -> Bool {
        guard let duration = finitePositive(seconds) else {
            return false
        }

        var changed = false
        if snapshot.duration != duration {
            snapshot.duration = duration
            changed = true
        }

        let position = clampPlaybackPosition(snapshot.position, to: duration)
        if snapshot.position != position {
            snapshot.position = position
            changed = true
        }

        if changed {
            refreshOutroBoundaryObserver()
        }

        return changed
    }

    func handleObservedDuration(
        _ observedDuration: TimeInterval?,
        observationGeneration: Int
    ) {
        guard observationGeneration == currentItemObservationGeneration,
              snapshot.currentEpisode != nil
        else {
            return
        }

        if updateDuration(from: observedDuration) {
            publishPlaybackState()
        } else {
            syncObservableState()
        }
    }

    private func refreshOutroBoundaryObserver() {
        guard let playerItem = player.currentItem,
              let cutoff = episodeBoundaries.outroCutoff(duration: resolvedDuration())
        else {
            removeOutroBoundaryObserver()
            return
        }
        guard outroBoundaryCutoff != cutoff else {
            return
        }

        removeOutroBoundaryObserver()
        outroBoundaryCutoff = cutoff
        let generation = currentItemObservationGeneration
        let boundaryTime = CMTime(seconds: playerTime(fromEpisode: cutoff), preferredTimescale: 600)
        outroBoundaryObserver = PlayerTimeObserver(token: player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: boundaryTime)],
            queue: .main
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      isCurrentItemCallback(playerItem, generation: generation)
                else {
                    return
                }
                handleOutroBoundaryReached(
                    cutoff,
                    observationGeneration: generation
                )
            }
        })
    }

    private func removeOutroBoundaryObserver() {
        if let outroBoundaryObserver {
            player.removeTimeObserver(outroBoundaryObserver.token)
            self.outroBoundaryObserver = nil
        }
        outroBoundaryCutoff = nil
    }

    func handleOutroBoundaryReached(
        _ cutoff: TimeInterval,
        observationGeneration: Int
    ) {
        guard observationGeneration == currentItemObservationGeneration,
              snapshot.currentEpisode != nil
        else {
            return
        }
        _ = completeAtOutroIfNeeded(
            previousPosition: snapshot.position,
            position: cutoff
        )
    }

    /// The periodic tick runs once a second of wall-clock time, so entering a
    /// zone between ticks would play up to a second of the ad (more at faster
    /// rates). A boundary at each zone start skips it on arrival.
    private func refreshSkipZoneBoundaryObservers() {
        removeSkipZoneBoundaryObservers()
        guard let playerItem = player.currentItem else {
            return
        }

        let generation = currentItemObservationGeneration
        skipZoneBoundaryObservers = playbackAdSkipPolicy.zones.map { zone in
            let boundaryTime = CMTime(seconds: playerTime(fromEpisode: zone.startTime), preferredTimescale: 600)
            return PlayerTimeObserver(token: player.addBoundaryTimeObserver(
                forTimes: [NSValue(time: boundaryTime)],
                queue: .main
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self,
                          isCurrentItemCallback(playerItem, generation: generation)
                    else {
                        return
                    }
                    handleSkipZoneBoundaryReached(
                        zone.startTime,
                        observationGeneration: generation
                    )
                }
            })
        }
    }

    private func removeSkipZoneBoundaryObservers() {
        for observer in skipZoneBoundaryObservers {
            player.removeTimeObserver(observer.token)
        }
        skipZoneBoundaryObservers = []
    }

    func handleSkipZoneBoundaryReached(
        _ startTime: TimeInterval,
        observationGeneration: Int
    ) {
        guard observationGeneration == currentItemObservationGeneration,
              snapshot.currentEpisode != nil,
              !hasFinishedCurrentEpisode
        else {
            return
        }
        evaluateAutoSkip(
            previousPosition: snapshot.position,
            position: startTime,
            cause: .acceptedTick
        )
    }

    private func isCurrentItemCallback(
        _ playerItem: AVPlayerItem,
        generation: Int
    ) -> Bool {
        generation == currentItemObservationGeneration
            && player.currentItem === playerItem
            && snapshot.currentEpisode != nil
    }

    var observationGenerationForTesting: Int {
        currentItemObservationGeneration
    }

    var outroBoundaryCutoffForTesting: TimeInterval? {
        outroBoundaryCutoff
    }

    var skipZoneBoundaryCountForTesting: Int {
        skipZoneBoundaryObservers.count
    }

    var isFinishLatchedForTesting: Bool {
        hasFinishedCurrentEpisode
    }

    private func markProgressBoundary() {
        snapshot.progressBoundaryID += 1
    }

    private func replaceSnapshot(_ snapshot: PlaybackSnapshot) {
        self.snapshot = snapshot
        syncObservableState()
    }

    private func syncObservableState() {
        setIfChanged(\.currentEpisode, to: snapshot.currentEpisode)
        setIfChanged(\.state, to: snapshot.state)
        setIfChanged(\.position, to: snapshot.position)
        setIfChanged(\.duration, to: snapshot.duration)
        let normalizedProgress = snapshot.normalizedProgress
        setIfChanged(\.progress, to: normalizedProgress)
        setIfChanged(\.progressBoundaryID, to: snapshot.progressBoundaryID)
        setIfChanged(\.rate, to: snapshot.rate)
        setIfChanged(\.sleepTimerEndsAt, to: snapshot.sleepTimerEndsAt)
        setIfChanged(\.skipZones, to: snapshot.skipZones)
        refreshPlaybackDiagnosticsText()
    }

    private func setIfChanged<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<AVFoundationPlaybackController, Value>,
        to value: Value
    ) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }

    private func rememberExpiredSleepTimer(mode: PlaybackSleepTimerMode, now: Date) {
        expiredSleepTimerMode = mode
        sleepTimerRearmDeadline = now.addingTimeInterval(Self.sleepTimerRearmWindow)
    }

    /// Re-arms the sleep timer that stopped playback if `now` is still inside
    /// the re-arm window; otherwise forgets it. `play` passes the wall clock;
    /// tests pass a shifted one.
    func rearmExpiredSleepTimerIfNeeded(now: Date) {
        guard let mode = expiredSleepTimerMode,
              let deadline = sleepTimerRearmDeadline,
              now <= deadline
        else {
            clearExpiredSleepTimerRearm()
            return
        }

        clearExpiredSleepTimerRearm()
        setSleepTimer(mode: mode, now: now)
    }

    private func clearExpiredSleepTimerRearm() {
        expiredSleepTimerMode = nil
        sleepTimerRearmDeadline = nil
    }

    private func clearSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerMode = .off
        snapshot.sleepTimerEndsAt = nil
        syncObservableState()
    }

    private func publishPlaybackState() {
        defer {
            syncObservableState()
        }

        guard snapshot.currentEpisode != nil else {
            mediaSession.clear()
            return
        }

        let duration = resolvedDuration()
        if let duration {
            snapshot.duration = duration
            snapshot.position = clampPlaybackPosition(snapshot.position, to: duration)
        } else if !snapshot.position.isFinite {
            snapshot.position = 0
        }

        mediaSession.publish(snapshot, resolvedDuration: duration)
    }

    private func recordDiagnosticsEvent(_ event: @autoclosure () -> String) {
        guard isPlaybackDiagnosticsEnabled || eventLogHandler != nil else {
            return
        }

        let message = event()
        if let eventLogHandler {
            let source = currentItemSourceIdentity.map { $0.kind == .localFile ? "local" : "stream" } ?? "none"
            eventLogHandler(
                "\(Date.now.ISO8601Format()) episode=\(snapshot.currentEpisode?.id.rawValue ?? "none") source=\(source) position=\(diagnosticsTime(snapshot.position)) duration=\(diagnosticsTime(resolvedDuration() ?? 0)) \(message)"
            )
        }
        guard isPlaybackDiagnosticsEnabled else {
            return
        }
        let timestamp = Date.now.formatted(.dateTime.hour().minute().second())
        playbackDiagnosticsEvents.append("[\(timestamp)] \(message)")
        if playbackDiagnosticsEvents.count > 80 {
            playbackDiagnosticsEvents.removeFirst(playbackDiagnosticsEvents.count - 80)
        }
    }

    private func refreshPlaybackDiagnosticsText() {
        guard isPlaybackDiagnosticsEnabled else {
            if !playbackDiagnosticsText.isEmpty {
                playbackDiagnosticsText = ""
            }
            return
        }

        let text = AVFoundationPlaybackDiagnosticsFormatter.text(
            snapshot: snapshot,
            player: player,
            item: player.currentItem,
            isPlaybackRequested: isPlaybackRequested,
            isAudioSessionActive: isAudioSessionActive,
            protectedPlaybackPosition: playbackPositionProtection.position,
            automaticTransientFailureRetryCount: playbackFailureRecoveryPolicy.automaticTransientFailureRetryCount,
            automaticTransientFailureRetryLimit: PlaybackFailureRecoveryPolicy.automaticTransientFailureRetryLimit,
            events: playbackDiagnosticsEvents
        )
        if playbackDiagnosticsText != text {
            playbackDiagnosticsText = text
        }
    }

    private func diagnosticsTime(_ value: TimeInterval?) -> String {
        AVFoundationPlaybackDiagnosticsFormatter.time(value)
    }

    private var diagnosticsTimeControlStatus: String {
        AVFoundationPlaybackDiagnosticsFormatter.timeControlStatus(player.timeControlStatus)
    }

    private func beginAudioSessionActivation() {
        guard audioSessionActivationTask == nil else {
            return
        }

        audioSessionActivationGeneration += 1
        let generation = audioSessionActivationGeneration
        let activation = audioSessionActivation
        let pendingDeactivation = audioSessionDeactivationTask
        snapshot.state = .loading
        publishPlaybackState()

        audioSessionActivationTask = Task { [weak self] in
            do {
                // A release still in flight from the previous unload has to reach
                // the media server before this activation does.
                await pendingDeactivation?.value
                let didRetry = try await activation()
                self?.completeAudioSessionActivation(
                    generation: generation,
                    didRetry: didRetry
                )
            } catch is CancellationError {
            } catch {
                self?.completeAudioSessionActivation(
                    generation: generation,
                    error: error
                )
            }
        }
    }

    private func completeAudioSessionActivation(
        generation: Int,
        didRetry: Bool
    ) {
        guard generation == audioSessionActivationGeneration else {
            // The orphaned task just activated the system session for a
            // generation invalidated mid-flight (unload during activation).
            // With no newer activation owning it, release it — otherwise the
            // system session stays active while isAudioSessionActive is false.
            if audioSessionActivationTask == nil, !isAudioSessionActive {
                scheduleAudioSessionDeactivation()
            }
            return
        }

        audioSessionActivationTask = nil
        isAudioSessionActive = true
        if didRetry {
            recordDiagnosticsEvent("audio session activated after retry")
        }
        guard isPlaybackRequested, snapshot.currentEpisode != nil else {
            return
        }
        requestPlaybackForCurrentItem()
    }

    private func completeAudioSessionActivation(
        generation: Int,
        error: any Error
    ) {
        guard generation == audioSessionActivationGeneration else {
            return
        }

        audioSessionActivationTask = nil
        isAudioSessionActive = false
        recordDiagnosticsEvent("audio session activation retry failed: \(error.localizedDescription)")
        guard isPlaybackRequested else {
            return
        }
        failPlayback(message: "Unable to activate audio session: \(error.localizedDescription)")
    }

    private func invalidateAudioSessionActivation() {
        audioSessionActivationGeneration += 1
        audioSessionActivationTask?.cancel()
        audioSessionActivationTask = nil
    }

    var currentPlayerRate: Float {
        player.rate
    }

    var currentPlayerDefaultRate: Float {
        player.defaultRate
    }

    var allowsExternalPlayback: Bool {
        player.allowsExternalPlayback
    }

    private func deactivateAudioSession() {
        guard isAudioSessionActive else {
            return
        }

        isAudioSessionActive = false
        scheduleAudioSessionDeactivation()
    }

    private func scheduleAudioSessionDeactivation() {
        let deactivation = audioSessionDeactivation
        audioSessionDeactivationTask = Task {
            do {
                try await deactivation()
            } catch {
                Self.logger.debug(
                    "Audio session deactivation failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}

/// A download and its trimmed copy, valid while the file is unchanged.
private struct SmartSpeedSource {
    let url: URL
    let fileIdentity: PlaybackLocalFileIdentity?
    let composition: SmartSpeedCompositionBuilder.Result

    func matches(_ url: URL, _ fileIdentity: PlaybackLocalFileIdentity?) -> Bool {
        self.url == url && self.fileIdentity == fileIdentity
    }
}
