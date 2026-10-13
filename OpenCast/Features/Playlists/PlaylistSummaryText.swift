import Foundation

/// A playlist's size line, "12 episodes · 6h 20m", read by VoiceOver as
/// "12 episodes, 6 hours 20 minutes". Grammar agreement resolves only on the
/// attributed localization path, so the counts go through `AttributedString`.
enum PlaylistSummaryText {
    static func line(itemCount: Int, totalDuration: TimeInterval) -> String {
        guard itemCount > 0 else {
            return "No episodes"
        }
        let episodes = inflectedEpisodes(itemCount)
        guard totalDuration > 0 else {
            return episodes
        }
        return "\(episodes) · \(PlaylistDurationFormat.short(totalDuration))"
    }

    static func spokenLine(itemCount: Int, totalDuration: TimeInterval) -> String {
        guard itemCount > 0 else {
            return "No episodes"
        }
        let episodes = inflectedEpisodes(itemCount)
        guard totalDuration > 0 else {
            return episodes
        }
        return "\(episodes), \(PlaylistDurationFormat.spoken(totalDuration))"
    }

    private static func inflectedEpisodes(_ count: Int) -> String {
        String(AttributedString(localized: "^[\(count) episode](inflect: true)").characters)
    }
}
