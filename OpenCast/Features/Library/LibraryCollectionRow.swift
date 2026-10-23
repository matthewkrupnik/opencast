import SwiftUI

/// One Library collection row: a tinted glyph in a fixed icon column, the
/// title and the item count (hidden at zero). The count is spoken through the containing control's value, so
/// it stays out of the label.
struct LibraryCollectionRow: View {
    let title: String
    let systemImage: String
    let count: Int
    let iconWidth: Double

    var body: some View {
        HStack(spacing: 10) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: iconWidth)
            }
            .labelStyle(.titleAndIcon)
            .labelIconToTitleSpacing(14)
            .frame(maxWidth: .infinity, alignment: .leading)

            if count > 0 {
                Text(count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .font(.title3)
        .frame(minHeight: 52)
        .contentShape(.rect)
    }
}

#Preview {
    VStack(spacing: 0) {
        LibraryCollectionRow(
            title: "Playlists",
            systemImage: "music.note.list",
            count: 4,
            iconWidth: 30
        )
        LibraryCollectionRow(
            title: "Up Next",
            systemImage: "text.line.first.and.arrowtriangle.forward",
            count: 0,
            iconWidth: 30
        )
    }
    .padding(.horizontal)
}
