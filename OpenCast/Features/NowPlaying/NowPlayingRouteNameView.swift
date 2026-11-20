import SwiftUI

/// Names the output playing when it is not the built-in speaker, e.g.
/// "AirPods Pro" or "Kitchen", so "why is nothing coming out?" has an answer
/// on Now Playing. Renders nothing for the built-in speaker or receiver.
struct NowPlayingRouteNameView: View {
    @Environment(OpenCastAppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var observer = AudioRouteObserver()

    var body: some View {
        let route = observer.route

        // A ZStack rather than a Group, so the task below still runs while
        // there is nothing to show.
        ZStack {
            if route.isExternal {
                Label(route.name, systemImage: route.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityLabel("Playing on \(route.name)")
                    .accessibilityIdentifier("Now Playing Route Name")
            }
        }
        // Only listen while the player is on screen; a fresh read on return
        // catches any change made while it was hidden.
        .task(id: isObserving) {
            guard isObserving else { return }
            await observer.observe()
        }
    }

    private var isObserving: Bool {
        appModel.isNowPlayingPresented && scenePhase == .active
    }
}
