import SwiftUI

/// The playlist palette as a row of swatches, the chosen one ringed.
struct PlaylistTintPicker: View {
    @Binding var selection: PlaylistTint

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PlaylistTint.allCases, id: \.self) { tint in
                Button {
                    selection = tint
                } label: {
                    swatch(tint)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(tint.title)
                .accessibilityAddTraits(tint == selection ? .isSelected : [])
                .accessibilityIdentifier("Playlist Color \(tint.title)")
            }
        }
        .padding(.vertical, 4)
    }

    private func swatch(_ tint: PlaylistTint) -> some View {
        Circle()
            .fill(tint.color)
            .frame(width: 28, height: 28)
            .padding(4)
            .overlay {
                if tint == selection {
                    Circle()
                        .strokeBorder(tint.color, lineWidth: 2.5)
                }
            }
            .contentShape(.circle)
    }
}

#Preview {
    @Previewable @State var selection = PlaylistTint.teal
    Form {
        PlaylistTintPicker(selection: $selection)
    }
}
