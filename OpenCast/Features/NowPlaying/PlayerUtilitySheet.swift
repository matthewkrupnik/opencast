import Foundation

nonisolated enum PlayerUtilitySheet: String, Identifiable, Sendable {
    case audio
    case sleep
    case chapters
    case notes
    case transcript
    case history

    var id: String { rawValue }
}
