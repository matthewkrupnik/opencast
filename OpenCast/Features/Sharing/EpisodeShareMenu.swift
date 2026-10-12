import SwiftUI

/// "Share Episode" for the episode menus. A child view so the state reads run
/// when the menu is realised, not in the host's body (menu and context-menu
/// builders run inline in their host).
struct EpisodeShareMenu: View {
    @Environment(OpenCastAppModel.self) private var appModel

    let episode: EpisodeListItemSnapshot

    var body: some View {
        if let context = EpisodeShareContext.make(episode: episode) {
            // Supplying the preview keeps the share sheet from fetching the
            // link's metadata before a target is chosen. No message: text
            // plus a URL makes Messages send a text bubble instead of a link.
            ShareLink(
                item: context.url,
                subject: Text(context.title),
                preview: SharePreview(context.title, image: previewImage(for: context))
            ) {
                Label("Share Episode", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func previewImage(for context: EpisodeShareContext) -> Image {
        if let artworkURL = context.artworkURL,
           let artwork = ArtworkLoader.shared.bestCachedImage(
               for: ArtworkRequest(url: artworkURL, targetPixelSize: CGSize(width: 512, height: 512))
           ) {
            return Image(uiImage: artwork)
        }
        return Image(appModel.appIcon.selection.previewImage)
    }
}

#Preview {
    NavigationStack {
        Text("Episode")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Episode Actions", systemImage: "ellipsis.circle") {
                        Section {
                            EpisodeShareMenu(episode: .previewSample)
                        }
                    }
                }
            }
    }
    .environment(OpenCastAppModel())
}
