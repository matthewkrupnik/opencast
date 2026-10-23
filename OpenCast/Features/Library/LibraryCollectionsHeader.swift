import SwiftUI

/// The Up Next row above the Library's playlists and shows. It opens the
/// queue sheet, so it has no chevron.
struct LibraryCollectionsHeader: View {
    @ScaledMetric(relativeTo: .title3) private var iconWidth = 30.0

    let upNextCount: Int
    let onOpenUpNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onOpenUpNext) {
                LibraryCollectionRow(
                    title: "Up Next",
                    systemImage: "text.line.first.and.arrowtriangle.forward",
                    count: upNextCount,
                    iconWidth: iconWidth
                )
            }
            .buttonStyle(.plain)
            .accessibilityValue(Self.accessibilityValue(for: upNextCount))
            .accessibilityIdentifier("Library Up Next Row")

            Divider()
                .padding(.leading, iconWidth + 14)
        }
    }

    private static func accessibilityValue(for count: Int) -> String {
        count > 0 ? count.formatted() : ""
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            LibraryCollectionsHeader(upNextCount: 2, onOpenUpNext: {})
                .padding(.horizontal, 20)
        }
        .navigationTitle("Library")
    }
}
