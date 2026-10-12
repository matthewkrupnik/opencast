import SwiftUI

/// Chapters & Summary entry states on episode detail — a per-episode manual
/// action below the show notes, offered for any episode with a completed
/// transcript but no current analysis. Failures render as the ready state
/// again (fail-open — never an error surface).
struct EpisodeChaptersSummaryControlsCard: View {
    enum Presentation: Equatable {
        case ready
        case running
        /// The feed declares `podcast:chapters`: creator metadata wins, so
        /// generation is not offered and the card explains why.
        case creatorChaptersAvailable
    }

    let presentation: Presentation
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Chapters & Summary", systemImage: "list.bullet.rectangle")
                .font(.headline)

            switch presentation {
            case .ready:
                Button("Generate Chapters & Summary", systemImage: "sparkles", action: onGenerate)
                    .buttonStyle(.glass)
            case .running:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Generating chapters and a summary…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .creatorChaptersAvailable:
                Text("This show publishes its own chapters for this episode, so OpenCast doesn’t generate them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }
}
