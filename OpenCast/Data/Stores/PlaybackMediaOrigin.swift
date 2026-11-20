import OpenCastPlayback

/// Where the bytes of the playing episode come from. Distinct from the
/// playlist "source" the Now Playing pill names: this answers whether a
/// stall can be the network's fault.
nonisolated enum PlaybackMediaOrigin: Equatable, Sendable {
    case downloaded
    case streaming

    /// Maps the live player item's kind, not the download record: a download
    /// that finishes mid-playback leaves the streamed item playing, so only
    /// the item says what is actually loaded. Nil when no item is loaded.
    init?(itemKind: PlaybackItemSourceIdentity.Kind?) {
        switch itemKind {
        case .localFile:
            self = .downloaded
        case .networkStream:
            self = .streaming
        case nil:
            return nil
        }
    }
}
