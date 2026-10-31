import OSLog

/// Why each automatic Detect Ads trigger did or didn't queue a pass. Logged
/// in every build (Console.app or a sysdiagnose, category `AutoDetectAds`),
/// so a missed pass on a Release install can be explained. Episode and show
/// identifiers are public: they are feed URLs and hashed episode IDs.
nonisolated enum AutoDetectAdsLog {
    private static let logger = Logger(subsystem: "mk.lan.opencast", category: "AutoDetectAds")

    static func record(_ message: String) {
        logger.log("\(message, privacy: .public)")
    }
}
