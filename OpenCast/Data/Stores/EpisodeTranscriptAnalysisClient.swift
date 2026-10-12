import Foundation

nonisolated protocol EpisodeTranscriptAnalysisClient: Sendable {
    func analyze(_ request: EpisodeTranscriptAnalysisAPIRequest) async throws -> EpisodeTranscriptAnalysisSubmitOutcome
    func pollJob(id: String) async throws -> EpisodeTranscriptAnalysisJobPollOutcome
}
