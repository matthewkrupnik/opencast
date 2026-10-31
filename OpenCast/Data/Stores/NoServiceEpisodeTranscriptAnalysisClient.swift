import Foundation

/// This build never had opencast's analysis service, so no earlier job can
/// exist to drain: every poll reads as an unknown job.
nonisolated struct NoServiceEpisodeTranscriptAnalysisClient: EpisodeTranscriptAnalysisClient {
    func pollJob(id: String) async throws -> EpisodeTranscriptAnalysisJobPollOutcome {
        throw EpisodeTranscriptAnalysisHTTPError(statusCode: 404, code: "job_not_found", detail: nil)
    }
}
