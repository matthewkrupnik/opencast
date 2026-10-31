import SwiftData

extension EpisodeAdFreePassCoordinator {
    func enqueue(
        episode: EpisodeListItemSnapshot,
        origin: AdFreePassQueueOrigin,
        context: AdFreePassEnqueueContext,
        modelContext: ModelContext,
        transcriptionEngine: AdFreePassTranscriptionEngine = .productDefault,
        podcastLanguageCode: String?,
        presentsKeyScreen: Bool = true,
        prepareBackgroundSession: @escaping @MainActor () -> Void = {},
        refreshSkipZones: @escaping @MainActor () async -> Int
    ) {
        enqueue(
            episode: episode,
            origin: origin,
            downloads: context.downloads,
            transcriptionModels: context.transcriptionModels,
            appleSpeechAssets: context.appleSpeechAssets,
            transcriptions: context.transcriptions,
            adAnalyses: context.adAnalyses,
            modelContext: modelContext,
            transcriptionEngine: transcriptionEngine,
            podcastLanguageCode: podcastLanguageCode,
            presentsKeyScreen: presentsKeyScreen,
            prepareBackgroundSession: prepareBackgroundSession,
            refreshSkipZones: refreshSkipZones
        )
    }

    func restorePersistedQueue(
        resolveEpisode: (String) -> EpisodeListItemSnapshot?,
        context: AdFreePassEnqueueContext,
        modelContext: ModelContext,
        podcastLanguageCode: (String) -> String?,
        refreshSkipZones: @escaping @MainActor (EpisodeListItemSnapshot) async -> Int
    ) {
        restorePersistedQueue(
            resolveEpisode: resolveEpisode,
            downloads: context.downloads,
            transcriptionModels: context.transcriptionModels,
            appleSpeechAssets: context.appleSpeechAssets,
            transcriptions: context.transcriptions,
            adAnalyses: context.adAnalyses,
            modelContext: modelContext,
            podcastLanguageCode: podcastLanguageCode,
            refreshSkipZones: refreshSkipZones
        )
    }
}
