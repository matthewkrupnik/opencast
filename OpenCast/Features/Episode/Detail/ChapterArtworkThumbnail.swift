import SwiftUI

/// A chapter list's leading square: the chapter's art, or an empty tile that
/// keeps the column aligned for chapters without any.
struct ChapterArtworkThumbnail: View {
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 40
    @State private var imageState = ArtworkImageState()

    let url: URL?

    var body: some View {
        let request = url.map {
            ArtworkRequest(url: $0, targetPixelSize: CGSize(width: side * displayScale, height: side * displayScale))
        }

        Group {
            if let image = imageState.resolvedImage(for: request) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
        .task(id: request) {
            guard let request else {
                return
            }
            _ = await imageState.loadArtwork(for: request, cacheKind: .episode)
        }
    }
}
