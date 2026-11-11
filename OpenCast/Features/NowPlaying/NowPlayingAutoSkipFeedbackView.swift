import SwiftUI

/// Scoped to one episode by the host's identity. It mounts with Now Playing,
/// so a skip that happened while it was closed never replays on opening.
struct NowPlayingAutoSkipFeedbackView: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.pinsAppStoreAutoSkipPill) private var pinsAutoSkipPill
    @State private var feedback = 0
    @State private var showsPill = false
    /// Whether the pill is up, for the host's status slot.
    @Binding var isShowingPill: Bool

    var body: some View {
        ZStack {
            if showsPill || pinsAutoSkipPill {
                NowPlayingAutoSkipPill(onUndo: undoLastAutoSkip)
                    .transition(.opacity)
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: feedback)
        .onChange(of: showsPill || pinsAutoSkipPill, initial: true) { _, isShowing in
            isShowingPill = isShowing
        }
        .onChange(of: appModel.playback.lastAutoSkipEvent) { _, event in
            guard event != nil, appModel.isNowPlayingPresented else { return }
            feedback += 1
            AccessibilityNotification.Announcement("Skipped promo").post()
            withAnimation(.easeOut(duration: 0.16)) { showsPill = true }
        }
        .onChange(of: appModel.isNowPlayingPresented) { _, isPresented in
            if !isPresented {
                withTransaction(\.disablesAnimations, true) { showsPill = false }
            }
        }
        .task(id: feedback) {
            guard feedback > 0 else { return }
            do {
                try await Task.sleep(for: .milliseconds(2500))
            } catch is CancellationError {
                return
            } catch {
                return
            }
            withAnimation(.easeOut(duration: 0.2)) { showsPill = false }
        }
    }

    private func undoLastAutoSkip() {
        appModel.undoLastAutoSkip()
        withAnimation(.easeOut(duration: 0.2)) { showsPill = false }
    }
}
