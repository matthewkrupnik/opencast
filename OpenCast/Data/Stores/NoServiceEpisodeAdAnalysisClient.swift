import Foundation

/// This build never had opencast's analysis service, so no earlier job can
/// exist to poll: every poll reads as an unknown job.
nonisolated struct NoServiceEpisodeAdAnalysisClient: EpisodeAdAnalysisClient {
    func pollJob(id: String) async throws -> EpisodeAdAnalysisJobPollOutcome {
        throw EpisodeAdAnalysisHTTPError(statusCode: 404, code: "job_not_found", detail: nil)
    }
}
