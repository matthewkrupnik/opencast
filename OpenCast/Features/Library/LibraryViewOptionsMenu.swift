import SwiftData
import SwiftUI

/// The Library's layout and sort menu: the shared `LayoutPickerMenu` plus
/// Sort By for the shows, bound to `LibraryDisplaySettingsStore`, and Sort
/// Playlists By, bound to `PlaylistDisplaySettingsStore`.
struct LibraryViewOptionsMenu: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @State private var selectionFeedbackTrigger = 0

    let resolvedLayout: LibraryLayout

    var body: some View {
        LayoutPickerMenu(layout: layoutBinding, resolvedLayout: resolvedLayout, title: "View Options") {
            Picker(selection: sortOrderBinding) {
                ForEach(LibrarySortOrder.allCases) { sortOrder in
                    Text(sortOrder.title)
                        .tag(sortOrder)
                }
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
            }
            .pickerStyle(.menu)

            Picker(selection: playlistSortOrderBinding) {
                ForEach(PlaylistSortOrder.allCases) { sortOrder in
                    Text(sortOrder.title)
                        .tag(sortOrder)
                }
            } label: {
                Label("Sort Playlists By", systemImage: "music.note.list")
            }
            .pickerStyle(.menu)
        }
        .accessibilityIdentifier("Library View Options")
        // Keyed to user picks, not the stored values: loading a stored
        // layout at launch or resizing an Automatic layout must not buzz.
        .sensoryFeedback(.selection, trigger: selectionFeedbackTrigger)
    }

    private var layoutBinding: Binding<LibraryLayoutPreference> {
        Binding {
            appModel.libraryDisplaySettings.layout
        } set: { layout in
            guard layout != appModel.libraryDisplaySettings.layout,
                  appModel.libraryDisplaySettings.setLayout(layout, modelContext: modelContext)
            else {
                return
            }
            selectionFeedbackTrigger += 1
        }
    }

    private var sortOrderBinding: Binding<LibrarySortOrder> {
        Binding {
            appModel.libraryDisplaySettings.sortOrder
        } set: { sortOrder in
            guard sortOrder != appModel.libraryDisplaySettings.sortOrder,
                  appModel.libraryDisplaySettings.setSortOrder(sortOrder, modelContext: modelContext)
            else {
                return
            }
            selectionFeedbackTrigger += 1
        }
    }

    private var playlistSortOrderBinding: Binding<PlaylistSortOrder> {
        Binding {
            appModel.playlistDisplaySettings.sortOrder
        } set: { sortOrder in
            guard sortOrder != appModel.playlistDisplaySettings.sortOrder,
                  appModel.setPlaylistSortOrder(sortOrder, modelContext: modelContext)
            else {
                return
            }
            selectionFeedbackTrigger += 1
        }
    }
}
