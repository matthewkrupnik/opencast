import SwiftUI

struct OpenCastRootLayerView<Content: View>: View {
    @Environment(OpenCastAppModel.self) private var appModel
    /// The scene's fold latch and Library layout memory, owned here so the
    /// tab root's content and the Now Playing cover read one value.
    @State private var sceneLibraryLayouts = SceneLibraryLayouts()

    /// An action from Now Playing that runs once the cover has gone, so
    /// navigation pushes land on the screen beneath it.
    @State private var actionAfterNowPlayingDismissal: (() -> Void)?

    let nowPlayingNamespace: Namespace.ID
    let onDismissNowPlaying: () -> Void
    let onOpenCurrentEpisode: () -> Void
    let onOpenCurrentPodcast: () -> Void
    let onOpenCurrentPlaylist: () -> Void
    let onStopPlayback: () -> Void
    let content: Content

    init(
        nowPlayingNamespace: Namespace.ID,
        onDismissNowPlaying: @escaping () -> Void,
        onOpenCurrentEpisode: @escaping () -> Void,
        onOpenCurrentPodcast: @escaping () -> Void,
        onOpenCurrentPlaylist: @escaping () -> Void,
        onStopPlayback: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.nowPlayingNamespace = nowPlayingNamespace
        self.onDismissNowPlaying = onDismissNowPlaying
        self.onOpenCurrentEpisode = onOpenCurrentEpisode
        self.onOpenCurrentPodcast = onOpenCurrentPodcast
        self.onOpenCurrentPlaylist = onOpenCurrentPlaylist
        self.onStopPlayback = onStopPlayback
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .fullScreenCover(
                    isPresented: nowPlayingPresented,
                    onDismiss: finishNowPlayingDismissal
                ) {
                    NowPlayingView(
                        onDismiss: { dismissNowPlaying() },
                        onOpenEpisode: { dismissNowPlaying(then: onOpenCurrentEpisode) },
                        onOpenPodcast: { dismissNowPlaying(then: onOpenCurrentPodcast) },
                        onOpenPlaylist: { dismissNowPlaying(then: onOpenCurrentPlaylist) },
                        onStopPlayback: { dismissNowPlaying(then: onStopPlayback) }
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Now Playing")
                    .accessibilityIdentifier("Now Playing")
                    .navigationTransition(.zoom(sourceID: NowPlayingView.transitionSourceID, in: nowPlayingNamespace))
                    .onAppear { nowPlayingProbeMark("card-settled") }
                    // The cover hides the screen beneath from accessibility,
                    // so it carries its own copy of the diagnostics readouts.
                    .overlay { diagnosticsStatus }
                }

            diagnosticsStatus

            #if DEBUG || OPENCAST_PERFORMANCE_PROBES
            if NowPlayingFramePacingProbe.shared.isEnabled {
                FrameProbeMarkButton()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
            #endif
        }
        .environment(sceneLibraryLayouts)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: SceneLibraryLayouts.divisionRegions(in: proxy), initial: true) { _, regions in
                        sceneLibraryLayouts.markFoldable(ifReported: regions)
                    }
            }
            .ignoresSafeArea()
        }
    }

    /// The 1 pt readouts UI tests read through the accessibility tree.
    @ViewBuilder
    private var diagnosticsStatus: some View {
        if appModel.exposesVoiceBoostDiagnosticsStatus,
           let voiceBoostDiagnostics = appModel.voiceBoostDiagnostics {
            VoiceBoostDiagnosticsStatusView(
                diagnostics: voiceBoostDiagnostics,
                playbackState: appModel.playback.state,
                playbackPosition: appModel.playback.position,
                hasEpisode: appModel.playback.currentEpisode != nil
            )
            .allowsHitTesting(false)
        }

        #if DEBUG || OPENCAST_PERFORMANCE_PROBES
        if NowPlayingFramePacingProbe.shared.isEnabled {
            NowPlayingFramePacingStatusView()
                .allowsHitTesting(false)
        }
        #endif
    }

    private var nowPlayingPresented: Binding<Bool> {
        Binding(
            get: { appModel.isNowPlayingPresented },
            set: { if !$0 { dismissNowPlaying() } }
        )
    }

    private func dismissNowPlaying(then action: (() -> Void)? = nil) {
        actionAfterNowPlayingDismissal = action
        appModel.isNowPlayingPresented = false
    }

    private func finishNowPlayingDismissal() {
        nowPlayingProbeMark("card-dismissed")
        onDismissNowPlaying()
        let action = actionAfterNowPlayingDismissal
        actionAfterNowPlayingDismissal = nil
        action?()
    }
}
