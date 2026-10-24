import Foundation

final class EpisodeTranscriptionWorkCoordinator {
    struct LocalReservation: Equatable {
        fileprivate let id = UUID()
        let episodeID: String
    }

    enum Conflict: Error, Equatable, LocalizedError {
        case anotherLocalTranscription
        case localTranscriptionForEpisode

        var errorDescription: String? {
            switch self {
            case .anotherLocalTranscription:
                "Another transcription is in progress."
            case .localTranscriptionForEpisode:
                "A local transcription of this episode is already in progress."
            }
        }
    }

    private var localReservationEpisodeID: String?
    private var localReservationIDs: Set<UUID> = []

    /// Whether a transcription request holds the episode, from its first
    /// step (download, model or asset preparation) to its release.
    func holdsReservation(forEpisodeID episodeID: String) -> Bool {
        localReservationEpisodeID == episodeID
    }

    func reserveLocal(episodeID: String) -> Result<LocalReservation, Conflict> {
        if localReservationEpisodeID != nil {
            return .failure(.anotherLocalTranscription)
        }

        let reservation = LocalReservation(episodeID: episodeID)
        localReservationEpisodeID = episodeID
        localReservationIDs.insert(reservation.id)
        return .success(reservation)
    }

    func joinLocal(episodeID: String) -> Result<LocalReservation, Conflict> {
        if let localReservationEpisodeID, localReservationEpisodeID != episodeID {
            return .failure(.anotherLocalTranscription)
        }

        let reservation = LocalReservation(episodeID: episodeID)
        localReservationEpisodeID = episodeID
        localReservationIDs.insert(reservation.id)
        return .success(reservation)
    }

    func releaseLocal(_ reservation: LocalReservation) {
        guard localReservationEpisodeID == reservation.episodeID,
              localReservationIDs.remove(reservation.id) != nil
        else {
            return
        }
        if localReservationIDs.isEmpty {
            localReservationEpisodeID = nil
        }
    }

    func localStartConflict(
        episodeID: String,
        reservation: LocalReservation?
    ) -> Conflict? {
        if localReservationEpisodeID != nil,
           reservation.map({ localReservationIDs.contains($0.id) }) != true {
            return .anotherLocalTranscription
        }
        return nil
    }
}
