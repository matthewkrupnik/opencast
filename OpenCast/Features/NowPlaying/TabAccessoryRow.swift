import SwiftUI

/// The mini player's expanded rows. `MiniPlayerView` offers them widest
/// first to a `ViewThatFits`, which draws the first whose ideal width fits
/// the accessory: each row's fixed parts, its title at `titleFloor` and, in
/// the wide row, the scrubber at `scrubberWidth`.
nonisolated enum TabAccessoryRow: Equatable, Sendable {
    /// A one-line title beside smaller artwork, for a narrow capsule.
    case dense
    /// The title over the show name, and play / pause.
    case standard
    /// The standard row with a scrubber, skip back and skip forward, for a
    /// wide capsule.
    case wide

    /// The least room a row's title asks for: what the dense row leaves its
    /// title in the narrowest accessory measured, the iPhone Duo's Closed
    /// capsule (290 pt).
    static let titleFloor: Double = 144

    /// The width at which one point of the scrubber's travel is one default
    /// skip forward (15 s, `PlaybackSkipIntervalOption.defaultForward`)
    /// through a 60-minute episode (3600 / 15), so the scrubber is never
    /// coarser than the skip button beside it. The 60 minutes is a typical
    /// episode length, an inference rather than a measurement.
    static let scrubberWidth: Double = 240

    var metrics: Metrics {
        switch self {
        case .dense:
            Metrics(
                horizontalPadding: 8,
                verticalPadding: 0,
                artworkSide: 30,
                artworkTitleSpacing: 8,
                controlSpacing: 2
            )
        case .standard:
            Metrics(
                horizontalPadding: 12,
                verticalPadding: 6,
                artworkSide: 38,
                artworkTitleSpacing: 10,
                controlSpacing: 8
            )
        case .wide:
            Metrics(
                horizontalPadding: 12,
                verticalPadding: 0,
                artworkSide: 38,
                artworkTitleSpacing: 10,
                controlSpacing: 8
            )
        }
    }

    /// One row's expanded geometry. The inline accessory keeps its own.
    struct Metrics: Equatable, Sendable {
        let horizontalPadding: Double
        let verticalPadding: Double
        let artworkSide: Double
        let artworkTitleSpacing: Double
        /// The gap between the title button and each control after it.
        let controlSpacing: Double
    }
}
