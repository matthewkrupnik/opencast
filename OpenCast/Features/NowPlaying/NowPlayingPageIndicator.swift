import SwiftUI

/// Dots under the paged area, one per page. Swiping turns the page, so the
/// dots only show where you are; VoiceOver adjusts them to turn it.
struct NowPlayingPageIndicator: View {
    let pages: [NowPlayingPage]
    let selection: NowPlayingPage
    let onSelect: (NowPlayingPage) -> Void

    private static let dotSide: CGFloat = 7

    var body: some View {
        HStack(spacing: 8) {
            ForEach(pages, id: \.self) { page in
                Circle()
                    .fill(page == selection ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(width: Self.dotSide, height: Self.dotSide)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement()
        .accessibilityLabel("Page")
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("Now Playing Page Indicator")
        .accessibilityAdjustableAction { direction in
            let offset = direction == .increment ? 1 : -1
            if let page = selection.neighbor(offset, in: pages) {
                onSelect(page)
            }
        }
    }

    private var accessibilityValue: String {
        let position = (pages.firstIndex(of: selection) ?? 0) + 1
        return "\(selection.title), \(position) of \(pages.count)"
    }
}
