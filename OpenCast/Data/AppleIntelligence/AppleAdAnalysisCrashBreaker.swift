import Foundation

/// Foundation Models can trap inside a Private Cloud Compute call (build 287:
/// `AppleGMSExecutor.publicError` asserting on an unmapped error), which no
/// `catch` reaches. Detect Ads resumes interrupted runs at launch, so one trap
/// became a crash loop. A marker is written before each Apple call and removed
/// after; a marker left by another process means that process died mid-call,
/// and Apple is skipped for a cooldown.
nonisolated struct AppleAdAnalysisCrashBreaker: Sendable {
    static let cooldown: TimeInterval = 24 * 60 * 60
    private static let currentProcessID = UUID().uuidString
    private static let inFlightKey = "adAnalysis.apple.inFlightProcessID"
    private static let suspendedUntilKey = "adAnalysis.apple.suspendedUntil"

    nonisolated(unsafe) private let defaults: UserDefaults
    private let processID: String
    private let now: @Sendable () -> Date

    init(
        defaults: UserDefaults = .standard,
        processID: String = Self.currentProcessID,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.defaults = defaults
        self.processID = processID
        self.now = now
    }

    func begin() {
        defaults.set(processID, forKey: Self.inFlightKey)
    }

    func end() {
        defaults.removeObject(forKey: Self.inFlightKey)
    }

    /// When Apple may be tried again, or nil when it may be tried now.
    func suspension() -> Date? {
        if let owner = defaults.string(forKey: Self.inFlightKey), owner != processID {
            defaults.removeObject(forKey: Self.inFlightKey)
            defaults.set(now().addingTimeInterval(Self.cooldown), forKey: Self.suspendedUntilKey)
        }
        guard let until = defaults.object(forKey: Self.suspendedUntilKey) as? Date, until > now() else {
            return nil
        }
        return until
    }
}
