import SwiftUI

struct SettingsHubTranscriptsSection: View {
    @Environment(OpenCastAppModel.self) private var appModel

    var body: some View {
        Section("Transcripts & Ads") {
            SettingsNavigationRow(
                title: "Transcription",
                systemImage: "waveform",
                route: .transcription,
                value: transcriptionValue
            )
            SettingsNavigationRow(
                title: "Ad Skipping",
                systemImage: "forward.end",
                route: .adSkipping
            )
            SettingsNavigationRow(
                title: AIServicesCopy.screenTitle,
                systemImage: "key",
                route: .aiServices,
                value: AIServicesCopy.hubValue(hasSavedKey: appModel.analysisKeys.hasSavedKey)
            )
        }
    }

    private var transcriptionValue: String {
        if appModel.transcriptionEngineSettings.prefersAppleSpeech,
           appModel.appleSpeechAssets.isTranscriberAvailable {
            return "Apple"
        }
        return "Whisper"
    }
}
