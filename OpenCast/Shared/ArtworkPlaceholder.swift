import SwiftUI

struct ArtworkPlaceholder: View {
    let title: String
    let imageURL: String?
    let displaySize: CGSize
    let targetPixelSize: CGSize?
    let cacheKind: ArtworkCacheKind
    let preview: ArtworkPreview?
    let contentMode: ContentMode
    /// Shrinks to the size its parent proposes, up to `displaySize`, still
    /// decoding for `displaySize` so one bitmap serves every size.
    let shrinksToFit: Bool
    let onPreviewResolved: ((ArtworkPreview) -> Void)?

    @State private var imageState = ArtworkImageState()
    @Environment(\.displayScale) private var displayScale

    init(
        title: String,
        imageURL: String?,
        size: CGFloat,
        targetPixelSize: CGSize? = nil,
        cacheKind: ArtworkCacheKind = .show,
        preview: ArtworkPreview? = nil,
        contentMode: ContentMode = .fill,
        shrinksToFit: Bool = false,
        onPreviewResolved: ((ArtworkPreview) -> Void)? = nil
    ) {
        self.init(
            title: title,
            imageURL: imageURL,
            displaySize: CGSize(width: size, height: size),
            targetPixelSize: targetPixelSize,
            cacheKind: cacheKind,
            preview: preview,
            contentMode: contentMode,
            shrinksToFit: shrinksToFit,
            onPreviewResolved: onPreviewResolved
        )
    }

    init(
        title: String,
        imageURL: String?,
        displaySize: CGSize,
        targetPixelSize: CGSize? = nil,
        cacheKind: ArtworkCacheKind = .show,
        preview: ArtworkPreview? = nil,
        contentMode: ContentMode = .fill,
        shrinksToFit: Bool = false,
        onPreviewResolved: ((ArtworkPreview) -> Void)? = nil
    ) {
        self.title = title
        self.imageURL = imageURL
        self.displaySize = displaySize
        self.targetPixelSize = targetPixelSize
        self.cacheKind = cacheKind
        self.preview = preview
        self.contentMode = contentMode
        self.shrinksToFit = shrinksToFit
        self.onPreviewResolved = onPreviewResolved
    }

    var body: some View {
        let request = artworkRequest

        ArtworkPlaceholderVisual(
            title: title,
            image: imageState.resolvedImage(for: request),
            preview: imageState.resolvedPreview(for: request, fallbackPreview: preview),
            contentMode: contentMode
        )
            .frame(
                minWidth: shrinksToFit ? 0 : displaySize.width,
                maxWidth: displaySize.width,
                minHeight: shrinksToFit ? 0 : displaySize.height,
                maxHeight: displaySize.height
            )
            .clipShape(.rect(cornerRadius: 8))
            .accessibilityHidden(true)
            .task(id: request) {
                guard let resolvedPreview = await imageState.loadArtwork(for: request, cacheKind: cacheKind) else {
                    return
                }

                onPreviewResolved?(resolvedPreview)
            }
    }

    private var artworkURL: URL? {
        guard let imageURL else {
            return nil
        }

        return URL(string: imageURL)
    }

    private var resolvedTargetPixelSize: CGSize {
        targetPixelSize ?? CGSize(
            width: displaySize.width * displayScale,
            height: displaySize.height * displayScale
        )
    }

    private var artworkRequest: ArtworkRequest? {
        guard let artworkURL else {
            return nil
        }

        return ArtworkRequest(url: artworkURL, targetPixelSize: resolvedTargetPixelSize)
    }
}
