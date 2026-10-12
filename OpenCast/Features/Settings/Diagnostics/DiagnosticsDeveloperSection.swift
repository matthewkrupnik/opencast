#if DEBUG
import SwiftUI

struct DiagnosticsDeveloperSection: View {
    @Environment(OpenCastAppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        Section("Developer") {
            Button(action: runOnboarding) {
                Label("Run Onboarding", systemImage: "sparkles.rectangle.stack")
            }

            if AdFreePassBackgroundProbe.isUserInterfaceEnabled {
                Button(action: runAdFreePassBackgroundProbe) {
                    Label("Ad-Free BG Probe", systemImage: "timer")
                }
                .accessibilityIdentifier("Settings Ad-Free Pass Background Probe")
            }

            Toggle(isOn: $appModel.replacesNowPlayingArtworkWithPlaybackDiagnostics) {
                Label("Playback Debug Artwork", systemImage: "terminal")
            }
        }
    }

    private func runOnboarding() {
        appModel.requestOnboardingPresentation()
    }

    private func runAdFreePassBackgroundProbe() {
        AdFreePassBackgroundProbe.startFromUserAction()
    }
}
#endif
