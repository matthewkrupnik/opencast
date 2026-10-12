import Foundation

public enum OpenCastWhisperModel: String, CaseIterable, Sendable {
    case largeV3 = "openai_whisper-large-v3-v20240930_626MB"

    public init?(commandLineValue value: String) {
        switch value {
        case "large", "large-v3", Self.largeV3.rawValue:
            self = .largeV3
        default:
            return nil
        }
    }

    public var defaultRemoteVersion: String {
        switch self {
        case .largeV3:
            "20240930_626MB-v1"
        }
    }
}
