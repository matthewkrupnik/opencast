import SwiftUI

/// The Shows row of Playlist Settings. It opens a sheet rather than a menu:
/// an iOS 27 menu rebuilds its open content whenever a value it reads
/// changes, so each pick in a long checklist snapped the list back to the
/// top, and a rebuild under a scrolling finger could land as a pick. A
/// sheet's list keeps its place while the rule changes under it.
///
/// The sheet is presented here rather than through `SheetDestination`
/// because a destination carries only identifiers, and the form knows only
/// the rule: it reports each change through `onChange` and the caller saves
/// it. Presenting from the row keeps every pick on that one save path, and
/// the sheet reads the saved rule each time the row re-renders.
struct PlaylistShowsRuleRow: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @State private var isPickerPresented = false

    let rule: PlaylistRule
    let onChange: (PlaylistRule) -> Void

    var body: some View {
        let title = rule.showsTitle(subscribedPodcastIDs: appModel.library.activePodcastIDs)
        Button(action: showPicker) {
            LabeledContent("Shows", value: title)
        }
        .foregroundStyle(.primary)
        .accessibilityIdentifier("Smart Rule Shows")
        .sheet(isPresented: $isPickerPresented) {
            PlaylistShowsPickerSheet(rule: rule, onChange: onChange)
                .environment(appModel)
        }
    }

    private func showPicker() {
        isPickerPresented = true
    }
}
