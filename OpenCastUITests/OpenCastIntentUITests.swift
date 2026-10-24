import AppIntentsTesting
import XCTest

final class OpenCastIntentUITests: XCTestCase {
    @MainActor
    func testSystemEpisodeQueryAndSearch() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--opencast-ui-testing", "--opencast-seed-ui-library", "--opencast-seed-episode-progress"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Library"].existsOrWait(timeout: 20))
        let definitions = IntentDefinitions(bundleIdentifier: "mk.lan.opencast")
        let episodes = try await definitions.entities["OpenCastEpisodeEntity"].suggestedEntities()
        XCTAssertFalse(episodes.isEmpty)
        try await definitions.intents["SearchOpenCastIntent"].makeIntent(query: "OpenCast").run()
        XCTAssertTrue(app.searchFields.firstMatch.existsOrWait(timeout: 10))
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "OpenCast")
        let missing = try await definitions.entities["OpenCastEpisodeEntity"].entities(identifiers: ["removed-episode"])
        XCTAssertTrue(missing.isEmpty)
    }

    @MainActor
    func testSystemPlaylistQueryAndPlay() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--opencast-ui-testing", "--opencast-seed-ui-library"]
        app.launchEnvironment["OPENCAST_SEED_PLAYLISTS"] = "1"
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Library"].existsOrWait(timeout: 20))
        let definitions = IntentDefinitions(bundleIdentifier: "mk.lan.opencast")
        let playlists = definitions.entities["OpenCastPlaylistEntity"]
        let suggested = try await playlists.suggestedEntities()
        XCTAssertEqual(suggested.count, 3)
        let commute = try XCTUnwrap(suggested.first { $0.identifier.instanceIdentifier == "ui-test-playlist-commute" })
        try await definitions.intents["PlayOpenCastPlaylistIntent"].makeIntent(playlist: commute).run()

        // The mini player's VoiceOver value is the assertable contract for the source line.
        let miniPlayer = app.buttons["Open Now Playing"].firstMatch
        XCTAssertTrue(miniPlayer.existsOrWait(timeout: 15))
        for _ in 0..<60 {
            if (miniPlayer.value as? String)?.contains("playing from Seeded Commute") == true { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertTrue(
            (miniPlayer.value as? String)?.contains("playing from Seeded Commute") == true,
            "Mini player value reads \(String(describing: miniPlayer.value))"
        )
    }
}
