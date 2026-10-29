import Foundation
import SwiftData

enum OpenCastModelContainerFactory {
    nonisolated static let cloudKitContainerIdentifier = "iCloud.mk.lan.opencast"
    static let syncedConfigurationName = "SyncedUserData"
    static let localConfigurationName = "LocalDeviceData"

    /// The models mirrored to iCloud; each is a `CD_`-prefixed record type.
    static let syncedModelTypes: [any PersistentModel.Type] = [
        SubscriptionRecord.self,
        EpisodeProgressRecord.self,
        SyncTombstoneRecord.self,
        PlaylistRecord.self,
        PlaylistItemRecord.self,
        PlaylistTombstoneRecord.self
    ]

    static var syncedSchema: Schema {
        Schema(syncedModelTypes)
    }

    static var localSchema: Schema {
        Schema([
            PodcastCacheRecord.self,
            EpisodeCacheRecord.self,
            RefreshLogRecord.self,
            LocalPreferenceRecord.self,
            EpisodeDownloadRecord.self,
            EpisodeTranscriptRecord.self,
            EpisodeAdAnalysisRecord.self,
            EpisodeTranscriptAnalysisRecord.self,
            AdFreePassQueueItemRecord.self,
            UpNextQueueItemRecord.self,
            ListeningHistoryRecord.self
        ])
    }

    static var fullSchema: Schema {
        Schema([
            SubscriptionRecord.self,
            EpisodeProgressRecord.self,
            SyncTombstoneRecord.self,
            PlaylistRecord.self,
            PlaylistItemRecord.self,
            PlaylistTombstoneRecord.self,
            PodcastCacheRecord.self,
            EpisodeCacheRecord.self,
            RefreshLogRecord.self,
            LocalPreferenceRecord.self,
            EpisodeDownloadRecord.self,
            EpisodeTranscriptRecord.self,
            EpisodeAdAnalysisRecord.self,
            EpisodeTranscriptAnalysisRecord.self,
            AdFreePassQueueItemRecord.self,
            UpNextQueueItemRecord.self,
            ListeningHistoryRecord.self
        ])
    }

    /// Where the device-local store lives, resolved the way `make` resolves
    /// it and without opening anything.
    static var localStoreURL: URL {
        ModelConfiguration(
            localConfigurationName,
            schema: localSchema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        ).url
    }

    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let syncedCloudKitDatabase: ModelConfiguration.CloudKitDatabase = inMemory
            ? .none
            : .private(cloudKitContainerIdentifier)

        let syncedConfiguration = ModelConfiguration(
            syncedConfigurationName,
            schema: syncedSchema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: syncedCloudKitDatabase
        )
        let localConfiguration = ModelConfiguration(
            localConfigurationName,
            schema: localSchema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: fullSchema,
            configurations: [syncedConfiguration, localConfiguration]
        )
    }
}
