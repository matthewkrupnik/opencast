import CoreGraphics
import Foundation
@preconcurrency import MediaPlayer

/// An immutable request can cross into the framework's Sendable artwork closure.
/// Its task owns loading on the loader's actor; only the decoded CGImage crosses back.
nonisolated final class MediaSessionArtworkRequest: Sendable {
    let id: String
    private let task: Task<CGImage, Error>

    @MainActor
    init(id: String, url: URL, fallbackURL: URL? = nil, loader: any NowPlayingArtworkLoading) {
        self.id = id
        task = Task { @MainActor in
            @MainActor func load(_ url: URL) async throws -> MPMediaItemArtwork {
                if let cached = loader.cachedArtwork(for: url) {
                    return cached
                }
                return try await loader.artwork(for: url)
            }
            let artwork: MPMediaItemArtwork
            do {
                artwork = try await load(url)
            } catch let error where !(error is CancellationError) {
                // Chapter art that fails to load shows the episode artwork.
                guard let fallbackURL else { throw error }
                artwork = try await load(fallbackURL)
            }
            try Task.checkCancellation()
            let image = artwork.image(at: artwork.bounds.size)
            #if os(macOS)
            let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            #else
            let cgImage = image?.cgImage
            #endif
            guard let cgImage else { throw NowPlayingArtworkError.invalidImageData }
            return cgImage
        }
    }

    deinit {
        task.cancel()
    }

    func cancel() {
        task.cancel()
    }

    func image() async throws -> CGImage {
        try Task.checkCancellation()
        guard !task.isCancelled else { throw CancellationError() }
        let image = try await task.value
        try Task.checkCancellation()
        guard !task.isCancelled else { throw CancellationError() }
        return image
    }
}
