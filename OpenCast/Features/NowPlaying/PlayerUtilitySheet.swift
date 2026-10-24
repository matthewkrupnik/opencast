import Foundation

enum PlayerUtilitySheet: String, Identifiable {
    case speed
    case sleep
    case chapters
    case transcript
    case history

    var id: String { rawValue }
}
