import Foundation
import Testing
@testable import OpenCast
@testable import OpenCastCore
@testable import OpenCastPlayback

@Suite("Scrub preview bubble")
struct NowPlayingScrubPreviewTests {
    private let chapters = PlaybackChapterList(
        chapters: [
            EpisodeChapter(id: 1, title: "Interview", startTime: 120),
            EpisodeChapter(id: 0, title: "Intro", startTime: 0),
            EpisodeChapter(id: 2, title: "Hidden art change", startTime: 200, isHidden: true),
        ],
        source: .embedded
    )
    private let zones = [PlaybackSkipZone(id: 1, startTime: 40, endTime: 60)]
    private let displayOnlyZones = [PlaybackSkipZone(id: 2, startTime: 300, endTime: 330)]

    private func preview(at time: TimeInterval, duration: TimeInterval? = 600) -> NowPlayingScrubPreview {
        NowPlayingScrubPreview(
            time: time,
            duration: duration,
            chapters: chapters,
            zones: zones,
            displayOnlyZones: displayOnlyZones
        )
    }

    @Test("Remaining time counts down from the target, and never goes negative")
    func remainingTime() {
        #expect(preview(at: 150).remaining == 450)
        #expect(preview(at: 700).remaining == 0)
    }

    @Test("An unknown or invalid duration leaves the remaining time out")
    func unknownDuration() {
        let durations: [Double?] = [nil, 0, -1, .nan, .infinity]
        for duration in durations {
            #expect(preview(at: 10, duration: duration).remaining == nil)
        }
    }

    @Test("The chapter is the last listed one that has started at the target, skipping hidden ones")
    func chapterAtTarget() {
        #expect(preview(at: 0).chapterTitle == "Intro")
        #expect(preview(at: 119).chapterTitle == "Intro")
        #expect(preview(at: 120).chapterTitle == "Interview")
        #expect(preview(at: 250).chapterTitle == "Interview")
    }

    @Test("No chapters, or a blank title, show no chapter line")
    func noChapterTitle() {
        let none = NowPlayingScrubPreview(time: 10, duration: 600, chapters: .empty, zones: [], displayOnlyZones: [])
        #expect(none.chapterTitle == nil)

        let blank = NowPlayingScrubPreview(
            time: 10,
            duration: 600,
            chapters: PlaybackChapterList(chapters: [EpisodeChapter(id: 0, title: "  ", startTime: 0)], source: .embedded),
            zones: [],
            displayOnlyZones: []
        )
        #expect(blank.chapterTitle == nil)
    }

    @Test("Zones are half-open: the start is inside, the end is past it")
    func zoneBounds() {
        #expect(preview(at: 39.9).zone == nil)
        #expect(preview(at: 40).zone == .adBreak)
        #expect(preview(at: 59.9).zone == .adBreak)
        #expect(preview(at: 60).zone == nil)
    }

    @Test("Display-only zones read as a possible ad")
    func displayOnlyZone() {
        #expect(preview(at: 310).zone == .possibleAd)
        #expect(preview(at: 330).zone == nil)
    }

    @Test("Where the tiers overlap, the auto-skip zone wins")
    func overlappingTiers() {
        let overlap = NowPlayingScrubPreview(
            time: 50,
            duration: 600,
            chapters: .empty,
            zones: zones,
            displayOnlyZones: [PlaybackSkipZone(id: 3, startTime: 30, endTime: 70)]
        )
        #expect(overlap.zone == .adBreak)
    }
}

@MainActor
@Suite("Scrub preview placement")
struct NowPlayingScrubPreviewPlacementTests {
    @Test("Centres the bubble on the thumb when it fits")
    func centred() {
        #expect(NowPlayingScrubPreviewPlacement.originX(centeredOn: 150, width: 100, containerWidth: 300) == 100)
    }

    @Test("Clamps the bubble inside the leading and trailing edges")
    func clampsAtEdges() {
        #expect(NowPlayingScrubPreviewPlacement.originX(centeredOn: 19, width: 100, containerWidth: 300) == 0)
        #expect(NowPlayingScrubPreviewPlacement.originX(centeredOn: 281, width: 100, containerWidth: 300) == 200)
    }

    @Test("A bubble as wide as the bar sits flush with its leading edge")
    func fullWidth() {
        #expect(NowPlayingScrubPreviewPlacement.originX(centeredOn: 250, width: 300, containerWidth: 300) == 0)
        #expect(NowPlayingScrubPreviewPlacement.originX(centeredOn: 250, width: 320, containerWidth: 300) == 0)
    }
}
