import SwiftData
import SwiftUI

struct OpenCastRootPresentationModifier: ViewModifier {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext

    @Binding var sheetDestination: SheetDestination?

    func body(content: Content) -> some View {
        @Bindable var appModel = appModel
        @Bindable var library = appModel.library

        content
            .sheet(item: $sheetDestination) { destination in
                SheetDestinationView(destination: destination, onDismiss: dismissSheet)
                    .environment(appModel)
                    .modelContext(modelContext)
            }
            // Now Playing's full-screen cover presents this alert while it is up.
            .playbackFailedAlert(isActive: !appModel.isNowPlayingPresented)
            .alert(
                "Playlist Error",
                item: $appModel.lastPlaylistError
            ) { _ in
            } message: { message in
                Text(message)
            }
            .alert(
                "Library Error",
                item: $library.lastErrorMessage
            ) { _ in
            } message: { message in
                Text(message)
            }
    }

    private func dismissSheet() {
        sheetDestination = nil
    }
}

extension View {
    /// The "Playback Failed" alert, presented from whichever layer is on top:
    /// the root, or Now Playing's full-screen cover while it is up.
    func playbackFailedAlert(isActive: Bool) -> some View {
        modifier(PlaybackFailedAlert(isActive: isActive))
    }
}

private struct PlaybackFailedAlert: ViewModifier {
    @Environment(OpenCastAppModel.self) private var appModel

    let isActive: Bool

    func body(content: Content) -> some View {
        content.alert(
            "Playback Failed",
            item: Binding(
                get: { isActive ? appModel.lastPlaybackError : nil },
                set: { appModel.lastPlaybackError = $0 }
            )
        ) { _ in
        } message: { message in
            Text(message)
        }
    }
}
