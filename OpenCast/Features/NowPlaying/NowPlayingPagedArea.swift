import SwiftUI

/// Now Playing's middle area: the artwork, then the chapters and the
/// transcript a swipe away, so the scrubber, transport, and toolbar stay
/// on screen while you read. It fills the rect its parent gives it; the
/// page indicator hangs just below that rect, in the gap the parent leaves.
///
/// A paging horizontal `ScrollView` rather than a page-style `TabView`:
/// its pages can come and go without the tab view's lost selection, and it
/// sizes to the parent's rect instead of claiming all the space offered.
struct NowPlayingPagedArea<Artwork: View>: View {
    let pages: [NowPlayingPage]
    let episodeID: String
    @Binding var selection: NowPlayingPage
    /// Turns the page from the indicator, animated per Reduce Motion.
    let onSelect: (NowPlayingPage) -> Void
    @ViewBuilder let artwork: Artwork

    var body: some View {
        // A lone artwork goes without the scroll view: even disabled, a
        // scroll view under the finger keeps the card's drag-to-dismiss from
        // starting.
        if pages.count < 2 {
            content(for: .artwork)
        } else {
            pager
        }
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(pages, id: \.self) { page in
                    content(for: page)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(page.title)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: scrollSelection)
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            NowPlayingPageIndicator(pages: pages, selection: selection, onSelect: onSelect)
                .alignmentGuide(.bottom) { $0[.top] }
        }
    }

    @ViewBuilder
    private func content(for page: NowPlayingPage) -> some View {
        switch page {
        case .artwork:
            artwork
        case .chapters:
            NowPlayingChapterList()
        case .transcript:
            // Built only once it's the page on screen: the transcript can
            // switch the player to its matched download when it appears,
            // which must not happen just because the pager laid it out next
            // door. Outside a navigation stack its title and toolbar don't
            // show; the sheet from More → Show Transcript still has them.
            if selection == .transcript {
                EpisodeTranscriptView(episodeID: episodeID)
            } else {
                Color.clear
            }
        }
    }

    private var scrollSelection: Binding<NowPlayingPage?> {
        Binding(
            get: { selection },
            set: { if let page = $0 { selection = page } }
        )
    }
}
