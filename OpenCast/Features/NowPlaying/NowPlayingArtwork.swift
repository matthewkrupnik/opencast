import SwiftUI

/// The playing episode's artwork, or the current chapter's art when the
/// chapter has its own. It fills the square its parent gives it.
struct NowPlayingArtwork: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    let title: String
    let imageURL: URL?

    @State private var imageState = ArtworkImageState()
    @State private var chapterImageState = ArtworkImageState()
    /// The chapter art being fetched, during which the previous chapter's stays up.
    @State private var pendingChapterRequest: ArtworkRequest?

    /// The widest the artwork gets, so one bitmap serves every size.
    private static let maximumSide: CGFloat = 500
    private static let cornerRadius: CGFloat = 8

    var body: some View {
        let request = artworkRequest
        let chapterRequest = chapterArtworkRequest
        let image = chapterImage(for: chapterRequest) ?? request.flatMap { imageState.resolvedImage(for: $0) }

        // The square comes from a shape, so a wide image fills it instead of
        // sizing it.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                NowPlayingArtworkImageView(title: title, image: image)
            }
            .clipShape(.rect(cornerRadius: Self.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .stroke(.white.opacity(colorScheme == .dark ? 0.24 : 0.34), lineWidth: 1)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Artwork for \(title)")
            .accessibilityIdentifier("Now Playing Artwork")
            .task(id: appModel.isNowPlayingPresented ? request : nil) {
                // Dismissal pauses loading without dropping the displayed bitmap.
                guard appModel.isNowPlayingPresented, let request else { return }
                _ = await imageState.loadArtwork(for: request, cacheKind: .episode)
            }
            .task(id: appModel.isNowPlayingPresented ? chapterRequest : nil) {
                guard appModel.isNowPlayingPresented, let chapterRequest else { return }
                pendingChapterRequest = chapterRequest
                _ = await chapterImageState.loadArtwork(for: chapterRequest, cacheKind: .episode)
                if pendingChapterRequest == chapterRequest {
                    pendingChapterRequest = nil
                }
            }
    }

    private var targetPixelSize: CGSize {
        CGSize(width: Self.maximumSide * displayScale, height: Self.maximumSide * displayScale)
    }

    private var artworkRequest: ArtworkRequest? {
        imageURL.map { ArtworkRequest(url: $0, targetPixelSize: targetPixelSize) }
    }

    private var chapterArtworkRequest: ArtworkRequest? {
        appModel.currentChapterArtworkURL.map { ArtworkRequest(url: $0, targetPixelSize: targetPixelSize) }
    }

    /// While the next chapter's art loads the previous chapter's stays up,
    /// so a chapter change doesn't flash the episode artwork in between. Art
    /// that fails to load falls back to the episode artwork.
    private func chapterImage(for request: ArtworkRequest?) -> UIImage? {
        guard let request else {
            return nil
        }
        if let image = chapterImageState.resolvedImage(for: request) {
            return image
        }
        return pendingChapterRequest == request ? chapterImageState.loadedImage : nil
    }
}
