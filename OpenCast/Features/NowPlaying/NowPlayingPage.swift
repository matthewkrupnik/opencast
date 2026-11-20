import Foundation

/// A page of Now Playing's middle area, in swipe order. The artwork always
/// leads; chapters and the transcript join only when there is something to
/// show, so the pager never offers an empty page.
nonisolated enum NowPlayingPage: Hashable, Sendable {
    case artwork
    case chapters
    case transcript

    static func pages(hasChapters: Bool, hasTranscript: Bool) -> [NowPlayingPage] {
        var pages: [NowPlayingPage] = [.artwork]
        if hasChapters { pages.append(.chapters) }
        if hasTranscript { pages.append(.transcript) }
        return pages
    }

    /// The selection to keep once `pages` changes: a page that went away
    /// falls back to the artwork rather than leaving the pager on nothing.
    static func resolved(_ selection: NowPlayingPage, in pages: [NowPlayingPage]) -> NowPlayingPage {
        pages.contains(selection) ? selection : .artwork
    }

    /// The page `offset` steps away in `pages`, or nil past either end.
    func neighbor(_ offset: Int, in pages: [NowPlayingPage]) -> NowPlayingPage? {
        guard let index = pages.firstIndex(of: self) else { return nil }
        let target = index + offset
        return pages.indices.contains(target) ? pages[target] : nil
    }

    /// The page's VoiceOver name.
    var title: String {
        switch self {
        case .artwork: "Artwork"
        case .chapters: "Chapters"
        case .transcript: "Transcript"
        }
    }
}
