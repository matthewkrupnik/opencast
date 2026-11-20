import AVFoundation
import Observation
import SwiftUI

/// Tracks the current audio output for the AirPlay button and the route name
/// on Now Playing. Each view owns one and drives it from `.task`, so
/// observing stops when the view goes away.
@MainActor
@Observable
final class AudioRouteObserver {
    private(set) var route = AudioRoute.builtIn

    /// Reads the route now, then again on every route change, until the
    /// calling task is cancelled.
    func observe() async {
        // The first read only catches up with the route already playing, so
        // it should not animate in.
        await refresh(disablesAnimations: true)
        for await _ in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
            await refresh(disablesAnimations: false)
        }
    }

    private func refresh(disablesAnimations: Bool) async {
        let route = await Self.currentRoute()
        guard !Task.isCancelled, self.route != route else { return }

        withTransaction(\.disablesAnimations, disablesAnimations) {
            self.route = route
        }
    }

    /// Off the main actor, because reading the route can wait on the audio server.
    @concurrent
    private static func currentRoute() async -> AudioRoute {
        AudioRoute(AVAudioSession.sharedInstance().currentRoute)
    }
}
