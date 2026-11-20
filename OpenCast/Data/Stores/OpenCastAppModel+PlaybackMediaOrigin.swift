import OpenCastPlayback

extension OpenCastAppModel {
    /// Whether the loaded episode plays from a download or streams; nil when
    /// nothing is loaded.
    var currentPlaybackMediaOrigin: PlaybackMediaOrigin? {
        // The item identity reads observation-ignored player state; every
        // item install and unload bumps the generation, so reading it makes
        // views refresh when the loaded item changes.
        _ = playback.currentItemGeneration
        return PlaybackMediaOrigin(itemKind: playback.currentItemSourceIdentity?.kind)
    }
}
