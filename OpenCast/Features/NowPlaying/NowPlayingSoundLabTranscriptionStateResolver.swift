nonisolated enum NowPlayingSoundLabTranscriptionStateResolver {
    static func activity(
        currentEpisodeID: String,
        requestEpisodeID: String?,
        storeEpisodeID: String?
    ) -> NowPlayingSoundLabTranscriptionActivity {
        if requestEpisodeID == currentEpisodeID || storeEpisodeID == currentEpisodeID {
            return .currentEpisode
        }
        if requestEpisodeID != nil || storeEpisodeID != nil {
            return .otherEpisode
        }
        return .none
    }
}
