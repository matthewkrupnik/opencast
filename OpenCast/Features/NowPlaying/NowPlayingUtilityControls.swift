import SwiftUI

/// The toolbar along the card's bottom edge: Close at the leading edge, More
/// at the trailing edge, and Audio and AirPlay grouped in the middle.
struct NowPlayingUtilityControls<MoreMenu: View>: View {
    /// The row's fixed height; the player keeps this much room clear at the
    /// end of its content so nothing scrolls to rest under the toolbar.
    static var height: CGFloat { 44 }

    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let rate: Float
    let onClose: () -> Void
    let onShowAudio: () -> Void
    @ViewBuilder let moreMenu: () -> MoreMenu

    var body: some View {
        // Close and More are the same width, so the equal spacers keep the
        // middle group centered. Glass marks each as a control: a circle at
        // either edge and one capsule around the middle group. Never
        // interactive glass: it takes the touches of the More menu's items
        // that open over it.
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 0) {
                toolbarButton("Close", systemImage: "chevron.down", action: onClose)
                    .glassEffect(.regular, in: .circle)
                    .accessibilityHint("Or drag the card down.")
                    .accessibilityIdentifier("Close Now Playing")

                Spacer(minLength: 8)

                HStack(spacing: 12) {
                    audioButton
                    AirPlayRoutePickerButton()
                }
                .padding(.horizontal, 10)
                .glassEffect(.regular, in: .capsule)

                Spacer(minLength: 8)

                // Its glass circle is on the menu's label (see
                // NowPlayingMoreMenu), not around the Menu.
                moreMenu()
            }
        }
        .font(.title3)
        // The row's height is fixed, so its icons stop growing here.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .foregroundStyle(.primary)
        .frame(height: Self.height)
    }

    private func toolbarButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .nowPlayingToolbarHitTarget()
        }
        .buttonStyle(.plain)
    }

    /// The waveform takes the tint when the speed is not 1x (the Audio sheet
    /// shows the number). While the sleep timer runs, a tinted moon follows
    /// with the time left; at accessibility sizes the moon stands alone.
    private var audioButton: some View {
        let mode = appModel.playback.sleepTimerMode
        // Ticks only while a timer runs on the visible player.
        return TimelineView(.animation(
            minimumInterval: 1,
            paused: mode == .off || !appModel.isNowPlayingPresented || scenePhase != .active
        )) { context in
            let remaining = appModel.playback.sleepTimerRemaining(at: context.date)
            let countdown = dynamicTypeSize.isAccessibilitySize
                ? nil
                : SleepTimerRemainingText.toolbarText(mode: mode, remaining: remaining)
            let spoken = SleepTimerRemainingText.spokenText(mode: mode, remaining: remaining)
            Button(action: onShowAudio) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .foregroundStyle(rate == 1 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                    if mode != .off {
                        HStack(spacing: 2) {
                            Image(systemName: "moon.zzz.fill")
                            if let countdown {
                                Text(countdown)
                                    .monospacedDigit()
                                    .contentTransition(.numericText(countsDown: true))
                            }
                        }
                        .font(.footnote.bold())
                        .foregroundStyle(.tint)
                        .transition(.opacity)
                    }
                }
                .nowPlayingToolbarHitTarget()
            }
            .buttonStyle(.plain)
            .animation(.snappy, value: mode)
            .animation(.snappy, value: countdown)
            .accessibilityLabel("Audio")
            .accessibilityValue(spoken.map { "\(rate.formattedSpeed), \($0)" } ?? rate.formattedSpeed)
            .accessibilityInputLabels(["Audio", "Speed", "Playback Speed", "Sleep Timer"])
        }
    }
}

extension View {
    func nowPlayingToolbarHitTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
    }
}
