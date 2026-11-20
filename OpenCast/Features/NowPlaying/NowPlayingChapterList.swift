import OpenCastCore
import SwiftData
import SwiftUI

/// The playing episode's chapters with the current one marked; a tap seeks
/// there. The Chapters sheet and Now Playing's Chapters page share it.
struct NowPlayingChapterList: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext

    /// Runs after a tap seeks; the sheet dismisses itself here, while the
    /// page stays put so the list keeps following playback.
    var onSelect: () -> Void = {}

    var body: some View {
        let chapters = appModel.currentEpisodeChapters
        let current = chapters.chapter(at: appModel.playback.position)

        List(chapters.chapters) { chapter in
            HStack(spacing: 4) {
                Button {
                    select(chapter, in: chapters)
                } label: {
                    HStack(spacing: 12) {
                        if chapters.hasChapterArt {
                            ChapterArtworkThumbnail(url: chapter.imageURL)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(EpisodeChaptersCard.startTimeText(chapter.startTime))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.tint)
                            Text(chapter.title)
                                .font(.body)
                                .fontWeight(chapter == current ? .semibold : .regular)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            if chapter == current {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .contentShape(.rect)
                }
                // Two tap targets share the row only with non-list button styles.
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Chapter, \(chapter.title), starts at \(EpisodeChaptersCard.startTimeText(chapter.startTime))"
                )
                .accessibilityValue(chapter == current ? "Now playing" : "")

                if let linkURL = chapter.linkURL {
                    ChapterLinkButton(url: linkURL, chapterTitle: chapter.title)
                }
            }
        }
        .listStyle(.plain)
    }

    private func select(_ chapter: EpisodeChapter, in chapters: PlaybackChapterList) {
        appModel.seekCurrentEpisode(toChapter: chapter, in: chapters, modelContext: modelContext)
        onSelect()
    }
}
