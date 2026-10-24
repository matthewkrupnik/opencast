import Foundation

nonisolated enum OpenCastSystemAction: Equatable, Sendable {
    case resume
    case playEpisode(String)
    case playLatest(String)
    case search(String)
    case playPlaylist(String)
}
