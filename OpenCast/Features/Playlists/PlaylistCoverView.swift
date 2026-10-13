import SwiftUI

/// A playlist's cover: the matched shows' card stack. It fills the square it
/// is offered; callers set the size, corner radius and any shadow.
struct PlaylistCoverView: View {
    let summary: PlaylistSummary
    let cornerRadius: Double

    var body: some View {
        SmartPlaylistCover(summary: summary, cornerRadius: cornerRadius)
    }
}
