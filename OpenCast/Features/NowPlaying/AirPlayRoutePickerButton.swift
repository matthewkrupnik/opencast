import SwiftUI

struct AirPlayRoutePickerButton: View {
    @State private var routeObserver = AudioRouteObserver()

    var body: some View {
        let route = routeObserver.route

        Label(
            "AirPlay",
            systemImage: route.isExternal ? "airplayaudio.circle.fill" : "airplayaudio"
        )
            .labelStyle(.iconOnly)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .contentTransition(.symbolEffect(.replace))
            .foregroundStyle(route.isExternal ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .nowPlayingToolbarHitTarget()
            .overlay {
                AirPlayRoutePickerUIView(routeName: route.name)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .task {
                await routeObserver.observe()
            }
    }
}
