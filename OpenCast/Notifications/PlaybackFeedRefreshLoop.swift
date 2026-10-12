import Foundation

/// Feed checks while audio keeps the app running in the background. Playback
/// holds the process awake, so these run on a steady interval instead of
/// waiting for iOS to grant a background refresh.
@MainActor
enum PlaybackFeedRefreshLoop {
    nonisolated static let interval: Duration = .seconds(30 * 60)

    /// Runs until cancelled. A tick refreshes only while `shouldRefresh`
    /// holds; the clock keeps counting while a paused app is suspended, so
    /// the overdue tick fires as soon as playback wakes it again.
    static func run(
        interval: Duration = interval,
        shouldRefresh: () -> Bool,
        refresh: () async -> Void,
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async {
        while !Task.isCancelled {
            do {
                try await sleep(interval)
            } catch {
                return
            }
            if shouldRefresh() {
                await refresh()
            }
        }
    }
}
