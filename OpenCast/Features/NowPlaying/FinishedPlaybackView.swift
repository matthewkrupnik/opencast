import SwiftUI

struct FinishedPlaybackView: View {
    @AccessibilityFocusState private var isFinishedStatusAccessibilityFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let presentation: FinishedPlaybackPresentation
    let artworkSide: CGFloat
    let onReplay: () -> Void
    let onDone: () -> Void

    var body: some View {
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        VStack(spacing: 12) {
            ArtworkPlaceholder(
                title: presentation.episode.podcastTitle,
                imageURL: presentation.episode.artworkURL,
                size: artworkSide,
                cacheKind: .episode,
                preview: presentation.episode.artworkPreview
            )

            VStack(spacing: 6) {
                Text(presentation.episode.title)
                    .font(isAccessibilitySize ? .headline : .title2)
                    .multilineTextAlignment(.center)
                    .lineLimit(isAccessibilitySize ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.episode.podcastTitle)
                    .font(isAccessibilitySize ? .subheadline : .title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(isAccessibilitySize ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label("Finished", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isFinishedStatusAccessibilityFocused)

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button("Replay", systemImage: "arrow.counterclockwise", action: onReplay)
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)

                    Button("Done", systemImage: "checkmark", action: onDone)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                }
            }
            .padding(.top, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Finished")
        .accessibilityIdentifier("Finished Playback")
        .task(id: presentation.episode.episodeID) {
            // Land VoiceOver on the status heading (the alert pattern) so the
            // state change is spoken before the actions. A ScreenChanged
            // notification with a string argument would reset focus to the
            // first on-screen element and race this move.
            await Task.yield()
            isFinishedStatusAccessibilityFocused = true
        }
    }
}
