import SwiftUI

struct NowPlayingChaptersView: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if appModel.currentEpisodeChapters.isEmpty {
                    ContentUnavailableView("No Chapters", systemImage: "list.bullet")
                } else {
                    NowPlayingChapterList(onSelect: { dismiss() })
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .accessibilityIdentifier("Now Playing Chapters")
    }
}
