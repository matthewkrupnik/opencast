import SwiftUI

/// The toolbar along the card's bottom edge: Close at the leading edge, More
/// at the trailing edge, and Audio, Sleep and AirPlay grouped in the middle.
struct NowPlayingUtilityControls<MoreMenu: View>: View {
    /// The row's fixed height; the player keeps this much room clear at the
    /// end of its content so nothing scrolls to rest under the toolbar.
    static var height: CGFloat { 44 }

    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase

    let rate: Float
    let onClose: () -> Void
    let onShowAudio: () -> Void
    let onShowSleepTimer: () -> Void
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
                    sleepTimerButton
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

    /// The speed shows beside the waveform whenever it is not 1x.
    private var audioButton: some View {
        Button(action: onShowAudio) {
            HStack(spacing: 3) {
                Image(systemName: "waveform")
                if rate != 1 {
                    Text(rate.formattedSpeed)
                        .font(.footnote.bold().monospacedDigit())
                }
            }
            .foregroundStyle(rate == 1 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
            .nowPlayingToolbarHitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Audio")
        .accessibilityValue(rate.formattedSpeed)
        .accessibilityInputLabels(["Audio", "Speed", "Playback Speed"])
    }

    private var sleepTimerButton: some View {
        TimelineView(.animation(
            minimumInterval: 1,
            paused: !appModel.isNowPlayingPresented || scenePhase != .active || appModel.playback.sleepTimerMode == .off
        )) { context in
            let isActive = appModel.playback.sleepTimerMode != .off
            Button(action: onShowSleepTimer) {
                Image(systemName: isActive ? "moon.zzz.fill" : "moon.zzz")
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .nowPlayingToolbarHitTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sleep Timer")
            .accessibilityValue(SleepTimerRemainingText.text(for: appModel.playback, at: context.date))
        }
    }
}

extension View {
    func nowPlayingToolbarHitTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
    }
}
