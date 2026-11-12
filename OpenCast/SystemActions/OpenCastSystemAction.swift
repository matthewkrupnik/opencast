import Foundation

nonisolated enum OpenCastSystemAction: Equatable, Sendable {
    case resume
    case pause
    case playEpisode(String)
    case playLatest(String)
    case search(String)
    case playPlaylist(String)
}
