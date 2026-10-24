import SwiftUI

struct NowPlayingUtilityControls: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    let rate: Float
    let onShowSpeed: () -> Void
    let onShowSleepTimer: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        playbackSpeedButton
                        AirPlayRoutePickerButton()
                    }
                    GridRow {
                        sleepTimerButton
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    playbackSpeedButton
                    AirPlayRoutePickerButton()
                    sleepTimerButton
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private var playbackSpeedButton: some View {
        PlayerUtilitySpeedButton(rate: rate, action: onShowSpeed)
    }

    private var sleepTimerButton: some View {
        TimelineView(.animation(
            minimumInterval: 1,
            paused: !appModel.isNowPlayingPresented || scenePhase != .active || appModel.playback.sleepTimerMode == .off
        )) { context in
            sleepTimerButton(
                value: sleepTimerText(at: context.date),
                progress: sleepTimerProgress(at: context.date)
            )
        }
    }

    private func sleepTimerButton(value: String, progress: Double?) -> some View {
        let isActive = appModel.playback.sleepTimerMode != .off
        return PlayerUtilityCircleButton(
            title: "Sleep",
            systemImage: isActive ? "moon.zzz.fill" : "moon.zzz",
            isActive: isActive,
            progress: progress,
            replacesSymbol: true,
            action: onShowSleepTimer
        )
        .accessibilityLabel("Sleep Timer")
        .accessibilityValue(value)
    }

    private func sleepTimerText(at date: Date) -> String {
        SleepTimerRemainingText.text(for: appModel.playback, at: date)
    }

    private func sleepTimerProgress(at date: Date) -> Double? {
        guard case .duration(let duration) = appModel.playback.sleepTimerMode,
              duration > 0,
              let remaining = appModel.playback.sleepTimerRemaining(at: date) else {
            return nil
        }

        return min(max(remaining / duration, 0), 1)
    }
}
