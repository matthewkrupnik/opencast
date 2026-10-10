import XCTest

extension XCTestCase {
    /// Opens a Settings hub row and waits for its sub-screen. A second tap on
    /// the Settings tab pops any pushed stack back to the hub first.
    @MainActor
    func openSettingsScreen(
        _ rowTitle: String,
        expecting screenTitle: String? = nil,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        openSection("Settings", in: app, file: file, line: line)
        if !app.navigationBars["Settings"].waitForExistence(timeout: 2) {
            openSection("Settings", in: app, file: file, line: line)
        }

        // The hub keeps its scroll offset across pushes, so walk back to the
        // top before scrolling down for rows below the fold.
        let row = app.buttons["Settings Row \(rowTitle)"].firstMatch
        var swipes = 0
        while !(row.waitForExistence(timeout: 1) && row.isHittable), swipes < 3 {
            app.swipeDown()
            swipes += 1
        }
        swipes = 0
        while !(row.waitForExistence(timeout: 1) && row.isHittable), swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(row.exists && row.isHittable, "Settings row \(rowTitle) should be hittable", file: file, line: line)
        row.tap()

        let title = screenTitle ?? rowTitle
        XCTAssertTrue(
            app.navigationBars[title].waitForExistence(timeout: 10),
            "\(title) screen should push from the Settings hub",
            file: file,
            line: line
        )
    }

    @MainActor
    func openSection(
        _ title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let tabButton = visibleTabButton(title, in: app) {
            tabButton.tap()
            return
        }

        XCTFail("\(title) navigation item should exist", file: file, line: line)
    }

    /// Opens the default All smart playlist, the list of new episodes that
    /// replaced the Inbox. The store creates it whenever no playlists exist,
    /// with a generated ID, so it is found by name.
    @MainActor
    func openAllPlaylist(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Already there: re-tapping the tab would pop to the collection and
        // push All again, moving rows mid-assertion.
        if app.navigationBars["All"].exists, app.tabBars.buttons["Playlists"].isSelected {
            return
        }
        openSection("Playlists", in: app, file: file, line: line)
        let allPlaylist = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "playlist-row-", "All"))
            .firstMatch
        XCTAssertTrue(allPlaylist.waitForExistence(timeout: 10), "All playlist should exist", file: file, line: line)
        allPlaylist.tap()
        XCTAssertTrue(
            app.navigationBars["All"].waitForExistence(timeout: 10),
            "All playlist should open",
            file: file,
            line: line
        )
    }

    /// An episode row by its `episode-row-` identifier, or the same episode's
    /// row in a smart playlist such as All.
    @MainActor
    func episodeListRow(_ rowIdentifier: String, in app: XCUIApplication) -> XCUIElement {
        let playlistIdentifier = rowIdentifier.replacingOccurrences(of: "episode-row-", with: "playlist-episode-")
        return app.buttons.matching(
            NSPredicate(format: "identifier == %@ OR identifier == %@", rowIdentifier, playlistIdentifier)
        ).firstMatch
    }

    @MainActor
    func visibleTabButton(
        _ title: String,
        in app: XCUIApplication
    ) -> XCUIElement? {
        let tabButton = app.tabBars.buttons[title]
        if tabButton.waitForExistence(timeout: 1), tabButton.isHittable {
            return tabButton
        }

        if let button = firstNonNavigationBarButton(title, in: app, timeout: 1) {
            return button
        }

        app.swipeDown()
        if tabButton.waitForExistence(timeout: 1), tabButton.isHittable {
            return tabButton
        }

        return firstNonNavigationBarButton(title, in: app, timeout: 1)
    }

    @MainActor
    private func firstNonNavigationBarButton(
        _ title: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> XCUIElement? {
        let predicate = NSPredicate(format: "label == %@", title)
        let buttons = app.buttons.matching(predicate)
        guard buttons.firstMatch.waitForExistence(timeout: timeout) else {
            return nil
        }

        let navigationBarFrames = navigationBarButtonFrames(title, in: app)
        for index in 0..<buttons.count {
            let button = buttons.element(boundBy: index)
            guard button.exists, button.isHittable else {
                continue
            }
            if !navigationBarFrames.contains(where: { $0.equalTo(button.frame) }) {
                return button
            }
        }

        return nil
    }

    @MainActor
    private func navigationBarButtonFrames(
        _ title: String,
        in app: XCUIApplication
    ) -> [CGRect] {
        let predicate = NSPredicate(format: "label == %@", title)
        let buttons = app.navigationBars.buttons.matching(predicate)
        guard buttons.firstMatch.exists else {
            return []
        }

        return (0..<buttons.count)
            .map { buttons.element(boundBy: $0) }
            .filter(\.exists)
            .map(\.frame)
    }
}
