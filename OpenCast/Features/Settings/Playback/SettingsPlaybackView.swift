import OpenCastPlayback
import SwiftData
import SwiftUI

struct SettingsPlaybackView: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section {
                Picker("Voice Boost", selection: voiceBoostModeBinding) {
                    ForEach(VoiceBoostMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Voice Boost")
                .accessibilityValue(appModel.playbackSettings.voiceBoostMode.fullTitle)

                if appModel.playbackSettings.voiceBoostMode == .perEpisode {
                    Toggle("On for New Episodes", isOn: voiceBoostPerEpisodeDefaultBinding)
                        .accessibilityIdentifier("playback-voice-boost-per-episode-default-toggle")
                }
            } header: {
                Text("Voice Boost")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lifts quiet voices and evens out volume.")
                    HelpFooterLink(title: "How Voice Boost works", topicID: HelpTopicID.voiceBoost)
                }
            }

            Section {
                Picker("Default Speed", selection: defaultSpeedBinding) {
                    ForEach(PlaybackRateSteps.steps, id: \.self) { speed in
                        Text(speed.formattedSpeed)
                            .tag(speed)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("playback-default-speed-picker")
            } header: {
                Text("Speed")
            } footer: {
                Text("Episodes play at this speed unless their show or the episode has its own.")
            }

            Section {
                Toggle("Enable Smart Speed", isOn: smartSpeedBinding)
            } header: {
                Text("Smart Speed")
            } footer: {
                Text("Dynamically shortens silences without distorting audio.")
            }

            Section("Skipping") {
                LabeledContent("Skip Back") {
                    Picker("Skip Back", selection: skipBackwardBinding) {
                        ForEach(PlaybackSkipIntervalOption.allCases) { option in
                            Label(option.label, systemImage: option.backwardSystemImage)
                                .tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                LabeledContent("Skip Forward") {
                    Picker("Skip Forward", selection: skipForwardBinding) {
                        ForEach(PlaybackSkipIntervalOption.allCases) { option in
                            Label(option.label, systemImage: option.forwardSystemImage)
                                .tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("playback-skip-forward-picker")
                }

                if let message = appModel.playbackSettings.lastErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("Sleep Timer") {
                NavigationLink("Presets", value: AppRoute.settings(.sleepTimer))
                    .accessibilityIdentifier("playback-sleep-timer-presets-row")
            }

            Section {
                Toggle("Show Note Button", isOn: privateNoteButtonsBinding)
                    .accessibilityIdentifier("playback-private-notes-toggle")
            } header: {
                Text("Private Notes")
            } footer: {
                Text("Adds a note button to Now Playing and a Notes section to the Library; notes stay on this device.")
            }

            Section {
                Toggle("Tap to Play", isOn: tapToPlayBinding)
                    .accessibilityIdentifier("playback-tap-to-play-toggle")
            } header: {
                Text("Episodes")
            } footer: {
                Text("When off, tapping an episode opens its details and the play button beside it starts playback.")
            }
        }
        .settingsSubscreen(title: "Playback")
    }

    private var voiceBoostModeBinding: Binding<VoiceBoostMode> {
        Binding {
            appModel.playbackSettings.voiceBoostMode
        } set: { mode in
            _ = appModel.setVoiceBoostMode(mode, modelContext: modelContext)
        }
    }

    private var voiceBoostPerEpisodeDefaultBinding: Binding<Bool> {
        Binding {
            appModel.playbackSettings.voiceBoostPerEpisodeDefault
        } set: { isEnabled in
            _ = appModel.setVoiceBoostPerEpisodeDefault(isEnabled, modelContext: modelContext)
        }
    }

    private var defaultSpeedBinding: Binding<Float> {
        Binding {
            PodcastPlaybackRateOverride.nearestStep(to: appModel.playbackSettings.globalPlaybackRate)
        } set: { rate in
            _ = appModel.setDefaultPlaybackRate(rate, modelContext: modelContext)
        }
    }

    private var smartSpeedBinding: Binding<Bool> {
        Binding {
            appModel.playbackSettings.isSmartSpeedEnabled
        } set: { enabled in
            _ = appModel.setSmartSpeedEnabled(enabled, modelContext: modelContext)
        }
    }

    private var skipBackwardBinding: Binding<PlaybackSkipIntervalOption> {
        Binding {
            appModel.playbackSettings.skipBackwardOption
        } set: { option in
            _ = appModel.setSkipBackwardOption(option, modelContext: modelContext)
        }
    }

    private var skipForwardBinding: Binding<PlaybackSkipIntervalOption> {
        Binding {
            appModel.playbackSettings.skipForwardOption
        } set: { option in
            _ = appModel.setSkipForwardOption(option, modelContext: modelContext)
        }
    }

    private var privateNoteButtonsBinding: Binding<Bool> {
        Binding {
            appModel.playbackSettings.showsPrivateNoteButtons
        } set: { isEnabled in
            _ = appModel.setPrivateNoteButtonsEnabled(isEnabled, modelContext: modelContext)
        }
    }

    private var tapToPlayBinding: Binding<Bool> {
        Binding {
            appModel.playbackSettings.isTapToPlayEnabled
        } set: { isEnabled in
            _ = appModel.setTapToPlayEnabled(isEnabled, modelContext: modelContext)
        }
    }
}
