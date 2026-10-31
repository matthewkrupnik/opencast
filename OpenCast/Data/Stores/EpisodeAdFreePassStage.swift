import OpenCastTranscription

enum EpisodeAdFreePassStage: Equatable {
    case idle
    case awaitingModelDownloadConsent(byteCount: Int64)
    case downloadingEpisode
    case installingModel(OpenCastWhisperModelInstallProgress)
    case installingSpeechAssets(fractionCompleted: Double)
    case transcribing(EpisodeTranscriptionProgress)
    /// Ad detection runs on this device. `nil` steps until the run's route
    /// is known.
    case analyzing(steps: EpisodeAdFreePassAnalysisSteps?)
    case completed(zoneCount: Int)
    case interrupted
    case failed(message: String)
    case unavailable(String)
}
