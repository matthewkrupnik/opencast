import SwiftUI

struct SettingsView: View {
    @Environment(OpenCastAppModel.self) private var appModel

    static let compactMiniPlayerScrollMargin = 132.0

    var body: some View {
        List {
            SettingsHubGeneralSection()
            SettingsHubTranscriptsSection()
            SettingsHubDataSection()
            SettingsHubHelpSection()
            SettingsHubAdvancedSection()
        }
        .labelStyle(SettingsLabelStyle())
        .navigationTitle("Settings")
        .contentMargins(.bottom, Self.compactMiniPlayerScrollMargin, for: .scrollContent)
        .task {
            appModel.appIcon.load()
            await appModel.syncStatus.refreshAccountStatus()
            appModel.cacheController.refreshSummaries()
        }
    }
}
