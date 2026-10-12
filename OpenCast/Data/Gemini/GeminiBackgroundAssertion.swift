import UIKit

/// Asks for background time while a foreground-started Gemini call finishes.
/// If iOS suspends the app anyway, the stores' resume path re-runs the
/// analysis on the next launch.
nonisolated enum GeminiBackgroundAssertion {
    static func run<T: Sendable>(
        named name: String,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        let token = await MainActor.run { BackgroundTaskToken(name: name) }
        defer {
            Task { @MainActor in token.end() }
        }
        return try await operation()
    }
}

@MainActor
private final class BackgroundTaskToken {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated {
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else {
            return
        }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
