import OpenCastCore
import SwiftData
import SwiftUI

struct NowPlayingView: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.modelContext) private var modelContext
    @State private var playPauseFeedback = 0
    @State private var skipFeedback = 0
    @State private var notePlaybackSession: EpisodeNotePlaybackSession?
    @State private var noteDraft: EpisodeNoteDraft?
    @State private var utilitySheet: PlayerUtilitySheet?
    @State private var isVoiceBoostEnabled = true
    /// The auto-skip pill is showing, so the source pill steps aside for it.
    @State private var isAutoSkipPillVisible = false
    @ScaledMetric(relativeTo: .body) private var playButtonScaledDiameter = NowPlayingTransportControls.playButtonBaseDiameter

    /// The window's safe area as it falls on the card.
    let safeAreaInsets: EdgeInsets
    let isTrackingDismissDrag: Bool
    let onDismiss: () -> Void
    let onOpenEpisode: () -> Void
    let onOpenPodcast: () -> Void
    let onOpenPlaylist: () -> Void
    let onStopPlayback: () -> Void

    /// The fixed row above the title: the source pill, or the auto-skip pill
    /// or a toast laid over it.
    private static let statusSlotHeight: CGFloat = NowPlayingSourcePill.height
    /// The Finished screen's artwork.
    private static let finishedArtworkSide: CGFloat = 240

    var body: some View {
        content
            .tint(.accentColor)
            .foregroundStyle(.primary)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: playPauseFeedback)
            .sensoryFeedback(.selection, trigger: skipFeedback)
            .accessibilityAction(.escape) {
                onDismiss()
            }
            .sheet(item: $noteDraft, onDismiss: resumePlaybackAfterNote) { draft in
                AddEpisodeNoteSheet(draft: draft)
                    .modelContext(modelContext)
            }
            .sheet(item: $utilitySheet) { sheet in
                utilitySheetContent(sheet)
            }
            .onChange(of: appModel.isNowPlayingPresented) { _, isPresented in
                if !isPresented { resetPresentation() }
            }
            .onChange(of: appModel.playbackSettings.isVoiceBoostEnabled) { _, _ in
                syncVoiceBoostEnabledFromStore()
            }
            .onChange(of: isVoiceBoostEnabled) { _, newValue in
                applyVoiceBoostEnabled(newValue)
            }
            .task(id: currentEpisodeID) {
                syncVoiceBoostEnabledFromStore()
            }
            .alert(
                "Playback Settings Error",
                item: playbackSettingsError
            ) { _ in
            } message: { message in
                Text(message)
            }
    }

    // MARK: Layout

    @ViewBuilder
    private var content: some View {
        if !appModel.isNowPlayingPresented {
            // The card is off screen: nothing is mounted, so none of its
            // controls stay in the accessibility tree. It builds again as the
            // card starts to present.
            Color.clear
        } else if let episode = appModel.playback.currentEpisode {
            player(for: episode)
        } else if let finishedPlaybackPresentation = appModel.finishedPlaybackPresentation {
            ScrollView {
                FinishedPlaybackView(
                    presentation: finishedPlaybackPresentation,
                    artworkSide: Self.finishedArtworkSide,
                    onReplay: replayFinishedPlayback,
                    onDone: onDismiss
                )
                .contentFrame(width: contentWidth)
                .padding(contentInsets)
            }
            .scrollIndicators(.hidden)
        } else {
            ContentUnavailableView("Nothing Playing", systemImage: "play.circle")
                .padding()
        }
    }

    /// The player never scrolls. The artwork takes the height the other
    /// rows leave and steps aside when that is too little; past that the
    /// title shrinks. Text stops growing at the first accessibility size.
    /// The toolbar stays on the card's bottom edge.
    private func player(for episode: Episode) -> some View {
        VStack(spacing: 0) {
            stack(for: episode)
                .contentFrame(width: contentWidth)
                .frame(maxHeight: .infinity)

            toolbar
                .contentFrame(width: contentWidth)
                .padding(.top, 38)
        }
        .padding(contentInsets)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .overlay(alignment: .top) {
            toast
                .padding(.top, contentInsets.top)
        }
        .overlay(alignment: .top) {
            autoSkipFeedback
                .padding(.top, contentInsets.top)
        }
        .animation(
            accessibilityReduceMotion ? .easeOut(duration: 0.2) : .bouncy,
            value: transcriptionRequest?.id
        )
        .animation(
            accessibilityReduceMotion ? nil : .easeOut(duration: 0.2),
            value: isPlaybackFailed
        )
    }

    private func stack(for episode: Episode) -> some View {
        PlayerStackLayout(minimumArtworkSide: 64) {
            statusSlot

            titleBlock(for: episode)
                .padding(.top, 12)
                .layoutValue(key: PlayerRow.self, value: .title)

            artwork(for: episode)
                .padding(.top, 12)
                .layoutValue(key: PlayerRow.self, value: .artwork)

            NowPlayingProgressSection(episodeID: episode.id.rawValue, onShowChapters: showChapters)
                .padding(.top, 32)

            failureBlock

            transport
                .padding(.top, 26)
        }
    }

    /// Insets from the card's edges: below the safe top, above the safe
    /// bottom, and the content's own clearances.
    private var contentInsets: EdgeInsets {
        let isRegular = horizontalSizeClass == .regular
        let sidePadding: CGFloat = isRegular ? 36 : 24
        return EdgeInsets(
            top: max(safeAreaInsets.top + 8, 16),
            leading: safeAreaInsets.leading + sidePadding,
            bottom: isRegular ? safeAreaInsets.bottom + 24 : max(safeAreaInsets.bottom, 16) + 4,
            trailing: safeAreaInsets.trailing + sidePadding
        )
    }

    private var contentWidth: CGFloat {
        horizontalSizeClass == .regular ? 500 : 430
    }

    // MARK: Rows

    /// The row above the title, at a fixed height: the source pill, which
    /// steps aside while the auto-skip pill or a toast shows over the slot.
    private var statusSlot: some View {
        ZStack {
            if let source = appModel.currentPlaylistSource,
               allowsSourcePill,
               !isAutoSkipPillVisible,
               transcriptionRequest == nil {
                NowPlayingSourcePill(name: source.name, action: openPlaylist)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.statusSlotHeight)
        .animation(.easeOut(duration: 0.2), value: isAutoSkipPillVisible)
        .animation(.easeOut(duration: 0.2), value: transcriptionRequest == nil)
    }

    @ViewBuilder
    private func artwork(for episode: Episode) -> some View {
        if appModel.replacesNowPlayingArtworkWithPlaybackDiagnostics {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        NowPlayingPlaybackDiagnosticsView(
                            text: appModel.playback.playbackDiagnosticsText
                                + appModel.playbackSourceIdentityDiagnostics,
                            size: proxy.size.width
                        )
                    }
                }
        } else {
            NowPlayingArtwork(title: episode.podcastTitle, imageURL: episode.artworkURL)
        }
    }

    private func titleBlock(for episode: Episode) -> some View {
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        return VStack(spacing: 6) {
            Button(action: openEpisode) {
                Text(episode.title)
                    .font(isAccessibilitySize ? .headline : .title2)
                    .multilineTextAlignment(.center)
                    .lineLimit(isAccessibilitySize ? 3 : 2)
                    .minimumScaleFactor(0.5)
            }
            .buttonStyle(.plain)
            .disabled(!canOpenCurrentEpisode)
            .accessibilityHint("Opens the episode description")
            .accessibilityIdentifier("Now Playing Episode Title")

            Button(action: openPodcast) {
                Text(episode.podcastTitle)
                    .font(isAccessibilitySize ? .subheadline : .title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.5)
            }
            .buttonStyle(.plain)
            .disabled(!canOpenCurrentPodcast)
            .accessibilityHint("Opens the show in your library")
            .accessibilityIdentifier("Now Playing Podcast Title")
        }
    }

    @ViewBuilder
    private var failureBlock: some View {
        if case .failed(let message) = appModel.playback.state {
            VStack(spacing: 8) {
                Label("Playback Failed", systemImage: "exclamationmark.triangle")
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Retry", systemImage: "arrow.clockwise", action: retryPlayback)
                    .buttonStyle(.glass)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .accessibilityElement(children: .combine)
            .transition(.opacity)
        }
    }

    private var transport: some View {
        NowPlayingTransportControls(
            playButtonDiameter: NowPlayingTransportControls.resolvedPlayButtonDiameter(
                scaled: playButtonScaledDiameter,
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
            ),
            skipBackwardInterval: appModel.playbackSettings.skipBackwardOption.seconds,
            skipForwardInterval: appModel.playbackSettings.skipForwardOption.seconds,
            showsPauseButton: appModel.playback.state.showsPauseButton,
            showsLoadingIndicator: appModel.playback.state.showsLoadingIndicator,
            playbackStateText: appModel.playback.state.accessibilityDescription,
            onSkipBackward: skipBackward,
            onTogglePlayPause: togglePlayPause,
            onSkipForward: skipForward
        )
    }

    private var toolbar: some View {
        NowPlayingUtilityControls(
            rate: appModel.playback.rate,
            onClose: onDismiss,
            onShowAudio: { utilitySheet = .audio },
            onShowSleepTimer: { utilitySheet = .sleep }
        ) {
            NowPlayingMoreMenu(
                episode: presentedEpisodeSnapshot,
                hasTranscript: hasCompletedTranscript,
                canShowDescription: canOpenCurrentEpisode,
                canShowShow: canOpenCurrentPodcast,
                playlistSourceName: appModel.currentPlaylistSource?.name,
                showsPrivateNotes: appModel.playbackSettings.showsPrivateNoteButtons,
                onTranscriptAction: performTranscriptAction,
                onAddNote: addTimestampedNote,
                onShowNotes: { utilitySheet = .notes },
                onShowDescription: openEpisode,
                onShowShow: openPodcast,
                onShowPlaylist: openPlaylist,
                onShowHistory: { utilitySheet = .history },
                onStopPlayback: onStopPlayback
            )
        }
    }

    /// The auto-skip pill, centered in the status slot. It draws over a toast.
    @ViewBuilder
    private var autoSkipFeedback: some View {
        if let episodeID = appModel.playback.currentEpisode?.id {
            NowPlayingAutoSkipFeedbackView(isShowingPill: $isAutoSkipPillVisible)
                .id(episodeID)
                .frame(maxWidth: .infinity, minHeight: Self.statusSlotHeight)
        }
    }

    /// A toast starts at the status slot's top and runs down over the title
    /// while it shows.
    @ViewBuilder
    private var toast: some View {
        if let transcriptionRequest {
            NowPlayingTranscriptionToast(
                request: transcriptionRequest,
                canOpenEpisode: canOpenCurrentEpisode,
                onOpenEpisode: openEpisodeFromTranscriptionToast,
                onDismiss: dismissTranscriptionToast
            )
            .padding(.horizontal, 16)
            .transition(
                accessibilityReduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
        }
    }

    @ViewBuilder
    private func utilitySheetContent(_ sheet: PlayerUtilitySheet) -> some View {
        switch sheet {
        case .audio:
            NowPlayingAudioSheet(
                voiceBoostEnabled: $isVoiceBoostEnabled,
                voiceBoostControlEnabled: appModel.playbackSettings.canChangeCurrentEpisodeVoiceBoost
            )
            .environment(appModel)
            .modelContext(modelContext)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        case .sleep:
            SleepTimerView()
                .environment(appModel)
                .modelContext(modelContext)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .chapters:
            NowPlayingChaptersView()
                .environment(appModel)
                .modelContext(modelContext)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .notes:
            NavigationStack {
                if let episode = appModel.playback.currentEpisode {
                    EpisodeNotesList(episode: EpisodeListItemSnapshot(episode: episode)) { timestamp in
                        playNote(at: timestamp, episodeID: episode.id.rawValue)
                    }
                    .navigationTitle("Private Notes")
                    .navigationSubtitle(episode.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .accessibilityAction(.escape) { utilitySheet = nil }
                } else {
                    ContentUnavailableView("Nothing Playing", systemImage: "play.circle")
                }
            }
            .modelContext(modelContext)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        case .transcript:
            NavigationStack {
                if let currentEpisodeID {
                    EpisodeTranscriptView(episodeID: currentEpisodeID)
                } else {
                    ContentUnavailableView("Nothing Playing", systemImage: "play.circle")
                }
            }
            .environment(appModel)
            .modelContext(modelContext)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        case .history:
            NavigationStack {
                ListeningHistoryView()
            }
            .environment(appModel)
            .modelContext(modelContext)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: State

    /// The pill's footnote capsule outgrows its 44 pt frame at accessibility
    /// sizes, and compact height has no room to spare, so the More menu's
    /// "Show <playlist>" item is the route back there.
    private var allowsSourcePill: Bool {
        !dynamicTypeSize.isAccessibilitySize && verticalSizeClass != .compact
    }

    private var isPlaybackFailed: Bool {
        if case .failed = appModel.playback.state {
            true
        } else {
            false
        }
    }

    private var currentPodcastID: String? {
        appModel.playback.currentEpisode?.podcastID.rawValue
    }

    private var currentEpisodeID: String? {
        appModel.playback.currentEpisode?.id.rawValue
    }

    private var canOpenCurrentEpisode: Bool {
        guard appModel.isNowPlayingPresented, let currentEpisodeID else {
            return false
        }
        return appModel.library.episode(with: currentEpisodeID) != nil
            || appModel.downloads.record(for: currentEpisodeID) != nil
    }

    private var canOpenCurrentPodcast: Bool {
        guard appModel.isNowPlayingPresented, let currentPodcastID else {
            return false
        }
        return appModel.library.isActivelySubscribed(to: currentPodcastID)
    }

    private var hasCompletedTranscript: Bool {
        guard appModel.isNowPlayingPresented,
              let currentEpisodeID,
              let record = appModel.transcriptions.record(for: currentEpisodeID)
        else {
            return false
        }
        return record.state == .completed && record.transcriptRelativePath != nil
    }

    private var presentedEpisodeSnapshot: EpisodeListItemSnapshot? {
        guard appModel.isNowPlayingPresented, let currentEpisodeID else { return nil }
        return appModel.episodeSnapshot(for: currentEpisodeID)
    }

    private var playbackSettingsError: Binding<String?> {
        Binding(
            get: { appModel.isNowPlayingPresented ? appModel.playbackSettings.lastErrorMessage : nil },
            set: { if $0 == nil { appModel.playbackSettings.clearLastError() } }
        )
    }

    private var transcriptionRequest: EpisodeTranscriptionRequest? {
        guard appModel.isNowPlayingPresented,
              appModel.transcriptionRequests.isPresented,
              let request = appModel.transcriptionRequests.request,
              request.episodeID == currentEpisodeID
        else {
            return nil
        }
        return request
    }

    // MARK: Actions

    private func showChapters() {
        utilitySheet = .chapters
    }

    /// A completed transcript opens in its sheet once its document loads; a
    /// missing one starts the request flow.
    private func performTranscriptAction() {
        guard let currentEpisodeID else {
            return
        }
        let record = appModel.transcriptions.record(for: currentEpisodeID)
        guard record?.state == .completed, let relativePath = record?.transcriptRelativePath else {
            appModel.requestTranscriptForCurrentEpisode(modelContext: modelContext)
            return
        }

        Task {
            do {
                _ = try await appModel.transcriptions.loadDocument(for: currentEpisodeID)
                guard canCompleteTranscriptAction(episodeID: currentEpisodeID, relativePath: relativePath) else {
                    return
                }
                utilitySheet = .transcript
            } catch {
                guard canCompleteTranscriptAction(episodeID: currentEpisodeID, relativePath: relativePath) else {
                    return
                }
                appModel.transcriptions.markTranscriptDocumentUnavailable(
                    episodeID: currentEpisodeID,
                    modelContext: modelContext
                )
                appModel.requestTranscriptForCurrentEpisode(modelContext: modelContext)
            }
        }
    }

    private func canCompleteTranscriptAction(episodeID: String, relativePath: String) -> Bool {
        guard appModel.isNowPlayingPresented,
              utilitySheet == nil,
              currentEpisodeID == episodeID,
              let record = appModel.transcriptions.record(for: episodeID)
        else {
            return false
        }
        return record.state == .completed && record.transcriptRelativePath == relativePath
    }

    private func dismissTranscriptionToast() {
        guard let transcriptionRequest else {
            return
        }
        appModel.dismissTranscriptionRequest(id: transcriptionRequest.id)
    }

    private func openEpisodeFromTranscriptionToast() {
        guard canOpenCurrentEpisode else {
            return
        }
        dismissTranscriptionToast()
        openEpisode()
    }

    private func addTimestampedNote() {
        guard let episode = appModel.playback.currentEpisode else { return }
        let session = EpisodeNotePlaybackSession(
            episode: EpisodeListItemSnapshot(episode: episode),
            timestamp: appModel.playback.position,
            state: appModel.playback.state, pause: appModel.playback.pause,
            playbackIntentRevision: { appModel.playback.playbackIntentRevision }
        )
        notePlaybackSession = session
        noteDraft = session.draft
    }

    private func playNote(at timestamp: TimeInterval, episodeID: String) {
        guard appModel.playback.currentEpisode?.id.rawValue == episodeID else { return }
        appModel.playback.seek(to: timestamp, intent: .scrub)
        appModel.playback.play()
        utilitySheet = nil
    }

    private func resumePlaybackAfterNote() {
        let session = notePlaybackSession
        notePlaybackSession = nil
        session?.finish(
            currentEpisodeID: appModel.playback.currentEpisode?.id.rawValue,
            state: appModel.playback.state,
            playbackIntentRevision: appModel.playback.playbackIntentRevision,
            play: appModel.playback.play
        )
    }

    private func retryPlayback() {
        appModel.playback.play()
    }

    private func replayFinishedPlayback() {
        appModel.replayFinishedPlayback(modelContext: modelContext)
    }

    private func skipBackward() {
        skipFeedback += 1
        appModel.playback.skip(by: -appModel.playbackSettings.skipBackwardOption.seconds)
    }

    private func togglePlayPause() {
        playPauseFeedback += 1
        appModel.playback.togglePlayPause()
    }

    private func skipForward() {
        skipFeedback += 1
        appModel.playback.skip(by: appModel.playbackSettings.skipForwardOption.seconds)
    }

    private func resetPresentation() {
        withTransaction(\.disablesAnimations, true) {
            utilitySheet = nil
        }
    }

    private func openEpisode() {
        onOpenEpisode()
    }

    private func openPodcast() {
        onOpenPodcast()
    }

    private func openPlaylist() {
        onOpenPlaylist()
    }

    private func syncVoiceBoostEnabledFromStore() {
        isVoiceBoostEnabled = appModel.playbackSettings.isVoiceBoostEnabled
    }

    private func applyVoiceBoostEnabled(_ isEnabled: Bool) {
        guard let currentEpisodeID else {
            syncVoiceBoostEnabledFromStore()
            return
        }

        guard appModel.playbackSettings.isVoiceBoostEnabled != isEnabled
            || appModel.playbackSettings.currentEpisodeID != currentEpisodeID
        else {
            return
        }

        let didUpdate = appModel.setVoiceBoostEnabled(
            isEnabled,
            forEpisodeID: currentEpisodeID,
            podcastID: currentPodcastID,
            modelContext: modelContext
        )
        if !didUpdate {
            syncVoiceBoostEnabledFromStore()
        }
    }
}

private extension View {
    /// Centers the content at no more than `width`.
    func contentFrame(width: CGFloat) -> some View {
        frame(maxWidth: width)
            .frame(maxWidth: .infinity)
    }
}

nonisolated private enum PlayerRow: LayoutValueKey {
    case other, title, artwork
    static let defaultValue = PlayerRow.other
}

/// A vertical stack exactly the proposed height tall. The artwork row is a
/// square taking the height the other rows leave, as wide as the stack at
/// most; below `minimumArtworkSide` it steps aside. If the other rows still
/// do not fit, the title row gets what is left and its text shrinks. Rows
/// space themselves with their own top padding.
nonisolated private struct PlayerStackLayout: Layout {
    let minimumArtworkSide: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(width: width, height: proposal.height, subviews: subviews)
        return CGSize(width: width, height: proposal.height ?? rows.heights.reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(width: bounds.width, height: bounds.height, subviews: subviews)
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let height = rows.heights[index]
            let width = subview[PlayerRow.self] == .artwork ? rows.artworkSide : bounds.width
            subview.place(
                at: CGPoint(x: bounds.midX, y: y),
                anchor: .top,
                proposal: ProposedViewSize(width: width, height: height)
            )
            y += height
        }
    }

    private func rows(width: CGFloat, height viewportHeight: CGFloat?, subviews: Subviews) -> (heights: [CGFloat], artworkSide: CGFloat) {
        var heights = subviews.map { subview in
            subview[PlayerRow.self] == .artwork
                ? 0
                : subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        guard let viewportHeight else {
            return (heights, 0)
        }
        var room = viewportHeight - heights.reduce(0, +)
        var artworkSide: CGFloat = 0
        if let index = subviews.firstIndex(where: { $0[PlayerRow.self] == .artwork }) {
            // The row includes its top padding; the square is what the
            // padding leaves of it.
            let padding = subviews[index].sizeThatFits(ProposedViewSize(width: 0, height: 0)).height
            let side = min(width, room - padding)
            if side >= minimumArtworkSide {
                artworkSide = side
                heights[index] = side + padding
                room -= side + padding
            }
        }
        if room < 0, let index = subviews.firstIndex(where: { $0[PlayerRow.self] == .title }) {
            heights[index] = max(0, heights[index] + room)
        }
        return (heights, artworkSide)
    }
}
