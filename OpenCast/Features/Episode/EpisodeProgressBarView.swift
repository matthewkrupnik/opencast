import SwiftUI

struct EpisodeProgressBarView: View {
    let fractionCompleted: Double

    var body: some View {
        ProgressView(value: fractionCompleted.clamped01)
            .progressViewStyle(.linear)
            .animation(.easeOut(duration: 0.2), value: fractionCompleted)
            .accessibilityHidden(true)
    }
}
