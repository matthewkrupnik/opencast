/// The secondary pane's three modes (the fork has no Up Next). The selection lives in scene storage
/// under `sceneStorageKey`, so it survives live pose changes and comes back
/// with the scene's saved state.
nonisolated enum NowPlayingSecondaryPane: String, CaseIterable, Identifiable, Sendable {
    case transcript
    case chapters
    case showNotes

    static let sceneStorageKey = "nowPlayingSecondaryPane"
    static let pickerAccessibilityIdentifier = "Now Playing Secondary Pane"

    /// A missing or unrecognized stored value is Transcript.
    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .transcript
    }

    /// The pane mode an open utility sheet already shows, if any.
    init?(sheet: PlayerUtilitySheet) {
        switch sheet {
        case .chapters:
            self = .chapters
        case .transcript:
            self = .transcript
        case .speed, .sleep, .notes, .history, .soundLab:
            return nil
        }
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .transcript:
            "Transcript"
        case .chapters:
            "Chapters"
        case .showNotes:
            "Show Notes"
        }
    }

    var systemImage: String {
        switch self {
        case .transcript:
            "quote.bubble"
        case .chapters:
            "list.bullet"
        case .showNotes:
            "doc.plaintext"
        }
    }
}
