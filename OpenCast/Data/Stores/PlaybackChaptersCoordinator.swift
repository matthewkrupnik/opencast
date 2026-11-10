import Foundation
import Observation
import OpenCastCore
import OpenCastPlayback

@Observable
final class PlaybackChaptersCoordinator {
    private(set) var current: PlaybackChapterList = .empty
    /// The playing chapter's art, also handed to the system Now Playing
    /// surfaces. Nil means the episode artwork.
    private(set) var currentArtworkURL: URL?

    @ObservationIgnored private let playback: AVFoundationPlaybackController
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let transcriptions: EpisodeTranscriptionStore
    @ObservationIgnored private let transcriptAnalyses: EpisodeTranscriptAnalysisStore
    @ObservationIgnored private let feedChapters: PodcastChaptersLoader
    /// UI-test seam: served for every episode in place of any real lookup.
    @ObservationIgnored var uiTestOverride: PlaybackChapterList?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var itemObservationTask: Task<Void, Never>?
    @ObservationIgnored private var artworkObservationTask: Task<Void, Never>?
    @ObservationIgnored private var installedEpisodeID: String?
    @ObservationIgnored private var installedItemGeneration: Int?

    init(
        playback: AVFoundationPlaybackController,
        library: LibraryStore,
        transcriptions: EpisodeTranscriptionStore,
        transcriptAnalyses: EpisodeTranscriptAnalysisStore,
        feedChapters: PodcastChaptersLoader
    ) {
        self.playback = playback
        self.library = library
        self.transcriptions = transcriptions
        self.transcriptAnalyses = transcriptAnalyses
        self.feedChapters = feedChapters
        startItemObservation()
        startArtworkObservation()
    }

    deinit {
        itemObservationTask?.cancel()
        artworkObservationTask?.cancel()
    }

    func refreshForCurrentEpisode() {
        refreshTask?.cancel()
        guard let episode = playback.currentEpisode else {
            refreshTask = nil
            install(.empty, forEpisodeID: nil, itemGeneration: nil)
            return
        }

        let episodeID = episode.id.rawValue
        let itemGeneration = playback.currentItemGeneration
        // A list belongs to one player item. A download switch or a
        // failed-item rebuild changes the audio under the same episode, so
        // the old list clears until the new item's read lands.
        if installedEpisodeID != episodeID || installedItemGeneration != itemGeneration {
            install(.empty, forEpisodeID: episodeID, itemGeneration: itemGeneration)
        }
        refreshTask = Task { [weak self] in
            guard let self else {
                return
            }
            let list = await load(episodeID: episodeID)
            guard !Task.isCancelled,
                  playback.currentEpisode?.id.rawValue == episodeID,
                  playback.currentItemGeneration == itemGeneration
            else {
                return
            }
            install(list, forEpisodeID: episodeID, itemGeneration: itemGeneration)
        }
    }

    func refreshIfCurrentEpisode(episodeID: String) {
        guard playback.currentEpisode?.id.rawValue == episodeID else {
            return
        }
        refreshForCurrentEpisode()
    }

    /// Awaits the in-flight refresh, if any. Test hook.
    func waitForRefresh() async {
        await refreshTask?.value
    }

    /// Follows the player item itself, because not every install goes
    /// through the app model: a failed item is rebuilt inside the
    /// controller, and `unload()` has no refresh call of its own.
    private func startItemObservation() {
        let playback = playback
        itemObservationTask = Task { [weak self] in
            var lastGeneration = playback.currentItemGeneration
            for await generation in Observations({ playback.currentItemGeneration }) {
                guard !Task.isCancelled, let self else {
                    return
                }
                guard generation != lastGeneration else {
                    continue
                }
                lastGeneration = generation
                refreshForCurrentEpisode()
            }
        }
    }

    /// Follows the playhead through the art timeline. A list without art never
    /// reads the position, so it doesn't wake on every tick.
    private func startArtworkObservation() {
        let artworkURLs = Observations { [weak self] () -> URL? in
            guard let self, current.hasAnyArt else {
                return nil
            }
            return current.imageURL(at: playback.position)
        }
        artworkObservationTask = Task { [weak self] in
            for await url in artworkURLs {
                guard !Task.isCancelled, let self else {
                    return
                }
                guard url != currentArtworkURL else {
                    continue
                }
                currentArtworkURL = url
                playback.setChapterArtworkURL(url)
            }
        }
    }

    private func load(episodeID: String) async -> PlaybackChapterList {
        if let uiTestOverride {
            return uiTestOverride
        }
        if let embedded = try? await playback.loadCurrentItemChapters(), !embedded.isEmpty {
            return PlaybackChapterList(chapters: embedded, source: .embedded)
        }
        guard !Task.isCancelled else {
            return .empty
        }

        // Creator-declared chapters win over generated ones even when the
        // document can't be fetched; same rule the detail cards follow.
        if let declared = await library.episodeDetail(for: episodeID)?.chaptersURL {
            guard let url = URL(string: declared) else {
                return .empty
            }
            let chapters = await feedChapters.chapters(at: url)
            return chapters.isEmpty ? .empty : PlaybackChapterList(chapters: chapters, source: .feed)
        }

        guard transcriptAnalyses.record(for: episodeID)?.state == .completed,
              let transcriptDocument = try? await transcriptions.loadDocument(for: episodeID),
              let analysisDocument = try? await transcriptAnalyses.loadDocument(for: episodeID),
              !analysisDocument.chapters.isEmpty,
              await transcriptAnalyses.isCurrentAnalysisDocumentOffCaller(analysisDocument, for: transcriptDocument)
        else {
            return .empty
        }

        return PlaybackChapterList(
            chapters: analysisDocument.chapters.map(EpisodeChapter.init),
            source: .generated(transcriptSourceSHA256: transcriptDocument.sourceFileSHA256)
        )
    }

    private func install(_ list: PlaybackChapterList, forEpisodeID episodeID: String?, itemGeneration: Int?) {
        guard playback.currentEpisode?.id.rawValue == episodeID else {
            return
        }
        current = list
        installedEpisodeID = episodeID
        installedItemGeneration = itemGeneration
    }
}

extension EpisodeChapter {
    /// Generated chapters carry transcript segment bounds the player doesn't
    /// need; only the display fields and times cross over.
    init(_ chapter: EpisodeTranscriptAnalysisChapter) {
        self.init(
            id: chapter.id,
            title: chapter.title,
            startTime: chapter.startTime,
            endTime: chapter.endTime
        )
    }
}
