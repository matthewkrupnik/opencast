import Foundation
import Testing
@testable import OpenCast
@testable import OpenCastCore

@Suite("PlaybackChapterList")
struct PlaybackChapterListTests {
    private let list = PlaybackChapterList(
        chapters: [
            EpisodeChapter(id: 2, title: "Third", startTime: 600, endTime: 900),
            EpisodeChapter(id: 0, title: "First", startTime: 0, endTime: 120),
            EpisodeChapter(id: 1, title: "Second", startTime: 120, endTime: 600),
        ],
        source: .embedded
    )

    @Test("Sorts chapters by start time")
    func sorts() {
        #expect(list.chapters.map(\.title) == ["First", "Second", "Third"])
        #expect(list.ordinal(of: list.chapters[2]) == 3)
    }

    @Test("Current chapter is the last one that has started")
    func currentChapter() {
        #expect(list.chapter(at: 0)?.title == "First")
        #expect(list.chapter(at: 119.9)?.title == "First")
        #expect(list.chapter(at: 120)?.title == "Second")
        #expect(list.chapter(at: 10_000)?.title == "Third")
        #expect(PlaybackChapterList.empty.chapter(at: 10) == nil)
    }

    @Test("Next chapter is the first one starting after the position")
    func nextChapter() {
        #expect(list.nextChapter(after: 0)?.title == "Second")
        #expect(list.nextChapter(after: 120)?.title == "Third")
        #expect(list.nextChapter(after: 600) == nil)
    }

    @Test("Previous restarts the chapter when well into it, otherwise goes back one")
    func previousChapter() {
        #expect(list.previousChapter(before: 130)?.title == "Second")
        #expect(list.previousChapter(before: 121)?.title == "First")
        #expect(list.previousChapter(before: 2)?.title == nil)
        #expect(list.previousChapter(before: 10)?.title == "First")
    }

    @Test("Timeline markers skip the episode start")
    func markers() {
        #expect(list.timelineMarkers == [120, 600])
    }

    @Test("Previous steps past chapters that share a start")
    func previousChapterWithDuplicateStarts() {
        let list = PlaybackChapterList(
            chapters: [
                EpisodeChapter(id: 0, title: "First", startTime: 0, endTime: 60),
                EpisodeChapter(id: 1, title: "Second", startTime: 60, endTime: 60),
                EpisodeChapter(id: 2, title: "Third", startTime: 60, endTime: 120),
            ],
            source: .embedded
        )
        #expect(list.chapter(at: 60)?.title == "Third")
        // Within the restart threshold, Previous must reach a strictly
        // earlier start rather than the twin at 60, or it never leaves 60.
        #expect(list.previousChapter(before: 60)?.title == "First")
        #expect(list.previousChapter(before: 61)?.title == "First")
        #expect(list.previousChapter(before: 70)?.title == "Third")
    }

    @Test("Hidden chapters stay out of the list but drive the art until they end")
    func artTimeline() {
        let a = URL(string: "https://example.com/a.jpg")!
        let b = URL(string: "https://example.com/b.jpg")!
        let list = PlaybackChapterList(
            chapters: [
                EpisodeChapter(id: 0, title: "Open", startTime: 0, imageURL: a),
                EpisodeChapter(id: 1, title: "Art", startTime: 30, endTime: 45, imageURL: b, isHidden: true),
                EpisodeChapter(id: 2, title: "Talk", startTime: 60),
            ],
            source: .feed
        )

        #expect(list.chapters.map(\.title) == ["Open", "Talk"])
        #expect(list.chapter(at: 40)?.title == "Open")
        #expect(list.hasAnyArt)
        #expect(list.imageURL(at: 10) == a)
        #expect(list.imageURL(at: 40) == b)
        // Past the hidden chapter's end, the chapter underneath shows again.
        #expect(list.imageURL(at: 50) == a)
        #expect(list.imageURL(at: 70) == nil)
    }
}
