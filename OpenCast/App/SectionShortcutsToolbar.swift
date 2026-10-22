import SwiftUI

/// Overcast-style header shortcuts: Settings and Downloads share a capsule on
/// the leading edge and Search sits alone on the trailing edge. Each one only
/// switches tabs, so the tab bar stays the single source of navigation. Regular
/// width already lists every section in the sidebar, so the shortcuts are
/// compact-only.
struct SectionShortcutsToolbar: ViewModifier {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var selectedTab: AppSection

    func body(content: Content) -> some View {
        content.toolbar {
            if horizontalSizeClass == .compact {
                ToolbarItemGroup(placement: .topBarLeading) {
                    shortcut(.settings)
                    shortcut(.downloads)
                        .badge(appModel.downloads.activeDownloadCount)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    shortcut(.search)
                }
            }
        }
    }

    private func shortcut(_ section: AppSection) -> some View {
        Button(section.title, systemImage: section.systemImage) {
            selectedTab = section
        }
        .accessibilityIdentifier("Shortcut \(section.title)")
    }
}

extension View {
    func sectionShortcutsToolbar(selectedTab: Binding<AppSection>) -> some View {
        modifier(SectionShortcutsToolbar(selectedTab: selectedTab))
    }
}
