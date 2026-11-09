import OpenCastPlayback
import SwiftData
import SwiftUI

/// Speed, Smart Speed and Voice Boost for the playing episode. Each choice
/// here belongs to this episode only; Settings holds the defaults.
struct NowPlayingAudioSheet: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var errorMessage: String?

    /// Now Playing's switch, which saves the episode's choice when it changes.
    @Binding var voiceBoostEnabled: Bool
    let voiceBoostControlEnabled: Bool

    private var rate: Float { appModel.playback.rate }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(
                        label: {
                            Text(rate.formattedSpeed)
                                .font(.title2.bold().monospacedDigit())
                                .contentTransition(.numericText(value: Double(rate)))
                        },
                        // Nil at either end disables that button.
                        onIncrement: Self.faster(than: rate).map { speed in { step(to: speed) } },
                        onDecrement: Self.slower(than: rate).map { speed in { step(to: speed) } }
                    )
                    .accessibilityLabel("Playback Speed")
                    .accessibilityValue(rate.formattedSpeed)
                    .accessibilityIdentifier("audio-playback-speed-stepper")
                } header: {
                    Text("Playback Speed")
                }

                Section {
                    Toggle("Smart Speed", isOn: smartSpeedBinding)
                        .accessibilityIdentifier("audio-smart-speed-toggle")
                } footer: {
                    Text("Shortens silences.")
                }

                Section {
                    Toggle("Voice Boost", isOn: $voiceBoostEnabled)
                        .disabled(!voiceBoostControlEnabled)
                        .accessibilityIdentifier("audio-voice-boost-toggle")
                } footer: {
                    if !voiceBoostControlEnabled {
                        Text("Voice Boost follows Settings › Playback. Choose Per Episode there to set it here.")
                    }
                }
            }
            .navigationTitle("Audio")
            .navigationSubtitle("This Episode Only")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .animation(.snappy, value: rate)
            .sensoryFeedback(.selection, trigger: rate)
            .alert("Couldn’t Change Audio", item: $errorMessage) { _ in
            } message: { message in
                Text(message)
            }
        }
    }

    private var smartSpeedBinding: Binding<Bool> {
        Binding(
            get: { appModel.playbackSettings.effectiveSmartSpeedEnabled },
            set: { isOn in
                if !appModel.setEpisodeSmartSpeedEnabled(isOn, modelContext: modelContext) {
                    showSettingsError(fallback: "Smart Speed could not be saved.")
                }
            }
        )
    }

    private func step(to speed: Float) {
        if !appModel.setPlaybackRate(speed, modelContext: modelContext) {
            showSettingsError(fallback: "Playback speed could not be saved.")
        }
    }

    private func showSettingsError(fallback: String) {
        errorMessage = appModel.playbackSettings.lastErrorMessage ?? fallback
        appModel.playbackSettings.clearLastError()
    }

    /// The next step above `rate`, without wrapping; nil at the fastest. The
    /// tolerance keeps a rate that round-tripped through `Float` arithmetic
    /// from selecting itself, and an off-step rate (from Siri) moves to the
    /// nearest step in that direction.
    static func faster(than rate: Float) -> Float? {
        PlaybackRateSteps.steps.first { $0 > rate + 0.0001 }
    }

    /// The next step below `rate`; nil at the slowest.
    static func slower(than rate: Float) -> Float? {
        PlaybackRateSteps.steps.last { $0 < rate - 0.0001 }
    }
}
