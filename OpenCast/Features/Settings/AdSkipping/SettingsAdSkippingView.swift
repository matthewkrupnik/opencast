import SwiftData
import SwiftUI

struct SettingsAdSkippingView: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section {
                Toggle("Auto-Skip Promos & Ads", isOn: autoSkipBinding)

                if let message = appModel.playbackSettings.lastErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skips detected promos and ads while an episode plays.")
                    HelpFooterLink(title: "How ad detection works", topicID: HelpTopicID.adDetection)
                }
            }
        }
        .settingsSubscreen(title: "Ad Skipping")
    }

    private var autoSkipBinding: Binding<Bool> {
        Binding {
            appModel.playbackSettings.isAutoSkipPromosAndAdsEnabled
        } set: { isEnabled in
            _ = appModel.setAutoSkipPromosAndAdsEnabled(isEnabled, modelContext: modelContext)
        }
    }
}
