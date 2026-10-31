import Foundation

protocol EpisodeAudioDownloading: Sendable {
    nonisolated func download(
        from sourceURL: URL,
        to temporaryURL: URL,
        resume: EpisodeDownloadResumeContext?,
        onResponseMetadata: @escaping @MainActor @Sendable (EpisodeDownloadResponseMetadata) -> Void,
        progress: @escaping @MainActor @Sendable (_ bytesReceived: Int64, _ bytesExpected: Int64?) -> Void
    ) async throws

    /// Temporary file paths of downloads still running outside this process
    /// (a background session's tasks from an earlier launch).
    nonisolated func liveDetachedTemporaryPaths() async -> Set<String>
}

extension EpisodeAudioDownloading {
    nonisolated func liveDetachedTemporaryPaths() async -> Set<String> {
        []
    }
}
