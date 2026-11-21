import Foundation
import OpenCastPlayback

/// The sleep timer's one-line state, shared by the Audio sheet's row and the
/// timer list so the two surfaces cannot drift.
enum SleepTimerRemainingText {
    static func text(for playback: AVFoundationPlaybackController, at date: Date) -> String {
        text(mode: playback.sleepTimerMode, remaining: playback.sleepTimerRemaining(at: date))
    }

    static func text(mode: PlaybackSleepTimerMode, remaining: TimeInterval?) -> String {
        guard let remaining else {
            return mode == .endOfEpisode ? "Stop After This Episode" : "Off"
        }

        return remaining > 0 ? "-\(remaining.formattedPlaybackDuration)" : "Off"
    }

    /// The countdown beside the toolbar's moon: whole minutes, rounded up,
    /// so it changes once a minute, then seconds in the last minute. Nil for
    /// Stop After This Episode (the scrubber already shows that time) and
    /// when no timer is running.
    static func toolbarText(mode: PlaybackSleepTimerMode, remaining: TimeInterval?) -> String? {
        guard case .duration = mode, let remaining, remaining > 0 else {
            return nil
        }
        return remaining > 60 ? "\(Int(ceil(remaining / 60)))m" : remaining.formattedPlaybackDuration
    }

    /// What VoiceOver adds to the Audio button while a timer is running.
    static func spokenText(mode: PlaybackSleepTimerMode, remaining: TimeInterval?) -> String? {
        switch mode {
        case .off:
            return nil
        case .endOfEpisode:
            return "sleep timer, stops after this episode"
        case .duration:
            guard let remaining, remaining > 0 else {
                return nil
            }
            let duration = Duration.seconds(remaining > 60 ? ceil(remaining / 60) * 60 : ceil(remaining))
            return "sleep timer, \(duration.formatted(.units(allowed: [.minutes, .seconds], width: .wide))) left"
        }
    }
}
