import SwiftUI

/// The top of a playlist's detail screen: the name, how much there is to
/// hear (with a footnote when the rule came from a newer version of the
/// app), and Play, all in the playlist's tint. The rules are edited from the
/// toolbar menu's Playlist Settings. With episodes already in Up Next, Play
/// first asks whether to replace the queue or add the playlist after it.
struct PlaylistHeroHeader: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isConfirmingPlay = false
    @State private var replaceQueuedCount = 0

    let summary: PlaylistSummary
    let itemCount: Int
    let totalDuration: TimeInterval
    let primaryAction: PlaylistPrimaryAction
    let canPlay: Bool
    let onPlay: (PlaylistPlayMode) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(summary.name)
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                countLine
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("Playlist Count Line")

                if summary.rule == nil {
                    Text("These rules need a newer version of the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            playbackButtons
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .tint(summary.tint?.color)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Playlist Hero Header")
    }

    private var countLine: some View {
        Text(PlaylistSummaryText.line(itemCount: itemCount, totalDuration: totalDuration))
            .accessibilityLabel(PlaylistSummaryText.spokenLine(itemCount: itemCount, totalDuration: totalDuration))
    }

    private var playbackButtons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))

        return GlassEffectContainer(spacing: 12) {
            layout {
                Button(action: playTapped) {
                    Label(primaryAction.title, systemImage: "play.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(summary.tint?.prominentLabelColor ?? .white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("Playlist Play")
                .playlistReplaceConfirmation(
                    isPresented: $isConfirmingPlay,
                    queuedCount: replaceQueuedCount,
                    onChoose: onPlay
                )
            }
            .controlSize(.large)
            .disabled(!canPlay)
        }
    }

    // The queue is read at tap time rather than in `body` so the detail screen
    // does not re-render on every Up Next change.
    private func playTapped() {
        replaceQueuedCount = appModel.upNextQueue.items.count
        if replaceQueuedCount > 0 {
            isConfirmingPlay = true
        } else {
            onPlay(.replace)
        }
    }
}
