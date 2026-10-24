import Foundation

enum SettingsRoute: Hashable {
    case playback
    case appIcon
    case notifications
    case transcription
    case adSkipping
    case sync
    case storage
    case importExport
    case listeningHistory
    case help
    case helpTopic(id: String)
    case about
    case diagnostics
    case refreshLogs
    case deleteData
}
