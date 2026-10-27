import SwiftUI

/// A playlist's cover: its color as a soft gradient square with the
/// playlist symbol. The Library grid and the car's playlist rows both draw
/// it, so a playlist looks the same everywhere.
struct PlaylistCoverView: View {
    let tint: PlaylistTint
    let size: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        LinearGradient(
            colors: [tint.color.mix(with: .white, by: 0.22), tint.color.mix(with: .black, by: 0.12)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: size, height: size)
        .overlay {
            Image(systemName: PlaylistRowView.symbolName)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint.prominentLabelColor)
                .padding(size * 0.28)
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }
}
