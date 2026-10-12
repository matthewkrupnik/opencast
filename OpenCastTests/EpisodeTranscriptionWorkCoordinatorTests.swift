import Testing
@testable import OpenCast

@MainActor
@Suite("Episode transcription work coordination")
struct EpisodeTranscriptionWorkCoordinatorTests {
    @Test("Same-episode attachments keep the original local reservation alive")
    func sameEpisodeAttachmentsUseIndependentLeases() {
        let coordinator = EpisodeTranscriptionWorkCoordinator()
        guard case .success(let owner) = coordinator.reserveLocal(episodeID: "episode"),
              case .success(let attachment) = coordinator.joinLocal(episodeID: "episode")
        else {
            Issue.record("Expected both same-episode local leases to succeed")
            return
        }

        coordinator.releaseLocal(attachment)
        #expect(coordinator.reserveLocal(episodeID: "other")
            == .failure(.anotherLocalTranscription))

        coordinator.releaseLocal(owner)
        guard case .success(let next) = coordinator.reserveLocal(episodeID: "other") else {
            Issue.record("Expected new local work after every local lease released")
            return
        }
        coordinator.releaseLocal(next)
    }
}
