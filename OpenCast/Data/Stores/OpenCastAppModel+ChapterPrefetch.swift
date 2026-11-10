import Foundation

extension OpenCastAppModel {
    /// A downloaded episode should have its feed chapters and their art
    /// offline: the loader saves the document, and loading each image puts it
    /// in the artwork disk cache, which serves stale entries while it
    /// revalidates. Fail-open: nothing here reports an error.
    func prefetchChaptersForOffline(episodeID: String) {
        Task { [library, feedChapters] in
            guard let declared = await library.episodeDetail(for: episodeID)?.chaptersURL,
                  let url = URL(string: declared)
            else {
                return
            }
            let chapters = await feedChapters.chapters(at: url)
            var seen = Set<URL>()
            for imageURL in chapters.compactMap(\.imageURL) where !imageURL.isFileURL && seen.insert(imageURL).inserted {
                let request = ArtworkRequest(url: imageURL, targetPixelSize: CGSize(width: 1_024, height: 1_024))
                _ = try? await ArtworkLoader.shared.loadResult(for: request, cacheKind: .episode)
            }
        }
    }
}
