import SwiftUI

/// Opens a chapter's `url` from a chapter list row.
struct ChapterLinkButton: View {
    let url: URL
    let chapterTitle: String

    var body: some View {
        Link(destination: url) {
            Image(systemName: "link")
                .imageScale(.medium)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Open Link for \(chapterTitle)")
    }
}
