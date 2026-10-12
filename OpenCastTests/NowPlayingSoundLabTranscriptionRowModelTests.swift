import Testing
@testable import OpenCast

@Suite("Sound Lab transcription row model")
struct NowPlayingSoundLabTranscriptionRowModelTests {
    @Test("A completed transcript wins over every activity", arguments: [
        NowPlayingSoundLabTranscriptionActivity.none,
        .currentEpisode,
        .otherEpisode,
    ])
    func completedTranscriptWins(activity: NowPlayingSoundLabTranscriptionActivity) {
        let model = makeModel(hasCompletedTranscript: true, localActivity: activity)

        #expect(model.action == .showTranscript)
        #expect(model.title == "Show Transcript")
        #expect(model.systemImage == "text.quote")
        #expect(model.phase == .completed)
        #expect(model.isEnabled)
        #expect(model.accessibilityValue == "Transcript available")
    }

    @Test("No activity offers on-device transcription")
    func idleOffersTranscription() {
        assertLocalIdle(makeModel())
    }

    @Test("Current local activity shows progress")
    func currentLocalActivityIsRunning() {
        let model = makeModel(localActivity: .currentEpisode)

        #expect(model.action == .transcribeLocally)
        #expect(model.title == "Transcribe")
        #expect(model.phase == .running)
        #expect(!model.isEnabled)
        #expect(model.accessibilityValue == "Transcription in progress")
    }

    @Test("Another local request disables transcription")
    func otherLocalDisablesTranscription() {
        let local = makeModel(localActivity: .otherEpisode)
        #expect(!local.isEnabled)
        #expect(local.accessibilityValue == "Another transcription is in progress")
    }

    @Test("The accessibility identifier is stable across every presentation")
    func accessibilityIdentifierIsStable() {
        for completed in [false, true] {
            for activity in [
                NowPlayingSoundLabTranscriptionActivity.none,
                .currentEpisode,
                .otherEpisode,
            ] {
                let model = makeModel(hasCompletedTranscript: completed, localActivity: activity)

                #expect(model.accessibilityIdentifier
                    == "Now Playing Sound Lab Transcript Action")
            }
        }
    }

    private func makeModel(
        hasCompletedTranscript: Bool = false,
        localActivity: NowPlayingSoundLabTranscriptionActivity = .none
    ) -> NowPlayingSoundLabTranscriptionRowModel {
        NowPlayingSoundLabTranscriptionRowModel(
            hasCompletedTranscript: hasCompletedTranscript,
            localActivity: localActivity
        )
    }

    private func assertLocalIdle(
        _ model: NowPlayingSoundLabTranscriptionRowModel,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(model.action == .transcribeLocally, sourceLocation: sourceLocation)
        #expect(model.title == "Transcribe", sourceLocation: sourceLocation)
        #expect(model.systemImage == "waveform", sourceLocation: sourceLocation)
        #expect(model.phase == .idle, sourceLocation: sourceLocation)
        #expect(model.isEnabled, sourceLocation: sourceLocation)
        #expect(model.accessibilityValue.isEmpty, sourceLocation: sourceLocation)
    }
}

@Suite("Sound Lab transcription state resolver")
struct NowPlayingSoundLabTranscriptionStateResolverTests {
    @Test("Request-only activity covers download and model preparation")
    func requestOnlyActivity() {
        #expect(resolveActivity(requestEpisodeID: "current") == .currentEpisode)
    }

    @Test("Direct store-only activity is authoritative")
    func storeOnlyActivity() {
        #expect(resolveActivity(storeEpisodeID: "current") == .currentEpisode)
    }

    @Test("Request and store can consistently name the current episode")
    func bothSourcesNameCurrentEpisode() {
        #expect(resolveActivity(requestEpisodeID: "current", storeEpisodeID: "current") == .currentEpisode)
    }

    @Test("Current activity wins over inconsistent other activity")
    func currentWinsOverOther() {
        #expect(resolveActivity(requestEpisodeID: "other", storeEpisodeID: "current") == .currentEpisode)
    }

    @Test("Any non-current source resolves to other episode")
    func otherEpisodeActivity() {
        #expect(resolveActivity(requestEpisodeID: "other") == .otherEpisode)
    }

    @Test("No active sources resolves to none")
    func noActivity() {
        #expect(resolveActivity() == .none)
    }

    private func resolveActivity(
        requestEpisodeID: String? = nil,
        storeEpisodeID: String? = nil
    ) -> NowPlayingSoundLabTranscriptionActivity {
        NowPlayingSoundLabTranscriptionStateResolver.activity(
            currentEpisodeID: "current",
            requestEpisodeID: requestEpisodeID,
            storeEpisodeID: storeEpisodeID
        )
    }
}
