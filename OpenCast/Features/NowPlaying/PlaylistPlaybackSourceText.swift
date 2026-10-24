import Foundation

/// Copy for the "playing from a playlist" surfaces. Grammar agreement
/// resolves only on the attributed localization path, and that path also
/// parses Markdown inside interpolated values, so only the count phrase goes
/// through it; names and titles are interpolated with `String(localized:)`.
enum PlaylistPlaybackSourceText {
    /// The separately laid-out count segment of the mini player's second
    /// line, including its leading separator.
    static func miniPlayerRemainingSegment(remainingCount: Int) -> String {
        String(localized: " · \(remainingCount) left")
    }

    static func miniPlayerAccessibilityValue(title: String, name: String, remainingCount: Int) -> String {
        guard remainingCount >= 1 else {
            return String(localized: "\(title), playing from \(name)")
        }
        return String(localized: "\(title), playing from \(name), \(remainingCount) left")
    }

    static func pillLabel(name: String) -> String {
        String(localized: "Playing from \(name)")
    }

    static func showPlaylistMenuTitle(name: String) -> String {
        String(localized: "Show \(name)")
    }
}
