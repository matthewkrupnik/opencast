import AVFoundation
import Foundation
import Testing
@testable import OpenCastPlayback

@Suite("AVAssetChapterReader")
struct AVAssetChapterReaderTests {
    @Test("Reads ID3 chapters with titles and bounds")
    func readsChapters() async throws {
        let chapters = try await AVAssetChapterReader.chapters(in: AVURLAsset(url: fixture("ChapteredSilence.mp3")))

        #expect(chapters.map(\.id) == [0, 1, 2])
        #expect(chapters.map(\.title) == ["Intro", "Middle", "Outro"])
        #expect(chapters.map(\.startTime) == [0, 1, 2])
        #expect(chapters.map(\.endTime) == [1, 2, 3])
    }

    @Test("Writes art embedded in chapters to files, once per image")
    func readsChapterArt() async throws {
        let directory = URL.temporaryDirectory.appending(path: "ChapterArtTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let asset = AVURLAsset(url: fixture("ChapteredArtSilence.mp3"))
        let chapters = try await AVAssetChapterReader.chapters(in: asset, artworkDirectory: directory)

        #expect(chapters.map(\.title) == ["Intro", "Middle", "Outro"])
        let urls = chapters.map(\.imageURL)
        #expect(urls[1] == nil)
        let intro = try #require(urls[0])
        let outro = try #require(urls[2])
        #expect(intro != outro)
        #expect(intro.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
        #expect(try Data(contentsOf: intro).starts(with: [0x89, 0x50, 0x4E, 0x47]))

        let again = try await AVAssetChapterReader.chapters(in: asset, artworkDirectory: directory)
        #expect(again.map(\.imageURL) == urls)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
    }

    @Test("Returns empty for audio without a tag")
    func noTag() async throws {
        let chapters = try await AVAssetChapterReader.chapters(in: AVURLAsset(url: fixture("UntaggedSilence.mp3")))
        #expect(chapters.isEmpty)
    }

    /// Silent 8 kHz MP3s made with ffmpeg; the chaptered one carries three
    /// one-second ID3v2.3 `CHAP` frames and a `CTOC`. `ChapteredArtSilence`
    /// is the same audio with a 1×1 PNG `APIC` in the first and last `CHAP`.
    private func fixture(_ name: String) -> URL {
        URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)")
    }
}
