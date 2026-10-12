import Foundation

enum EpisodeTranscriptAnalysisError: LocalizedError, Sendable, Equatable {
    case clientDisabled
    case apiKeyMissing
    case transcriptNotCompleted
    case analysisDocumentMissing
    case anotherJobActive
    case analysisTimedOut

    var errorDescription: String? {
        switch self {
        case .clientDisabled:
            "Chapters & Summary is disabled in this build."
        case .apiKeyMissing:
            GeminiConfiguration.missingKeyMessage
        case .transcriptNotCompleted:
            "Complete the transcript before generating chapters and a summary."
        case .analysisDocumentMissing:
            "The Chapters & Summary file could not be found."
        case .anotherJobActive:
            "Finish the active Chapters & Summary run before starting another one."
        case .analysisTimedOut:
            "Chapters & Summary took too long. Try again."
        }
    }
}
