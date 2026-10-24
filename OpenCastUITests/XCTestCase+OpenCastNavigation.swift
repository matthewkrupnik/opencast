import XCTest

extension XCUIElement {
    /// `waitForExistence` makes its first check only after about a second,
    /// even when the element is already there; this returns at once then.
    func existsOrWait(timeout: TimeInterval) -> Bool {
        exists || waitForExistence(timeout: timeout)
    }

    /// The same shortcut for `waitForNonExistence`.
    func absentOrWait(timeout: TimeInterval) -> Bool {
        !exists || waitForNonExistence(timeout: timeout)
    }
}

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
        if !app.navigationBars["Settings"].existsOrWait(timeout: 2) {
            openSection("Settings", in: app, file: file, line: line)
        }

        // The hub keeps its scroll offset across pushes, so walk back to the
        // top before scrolling down for rows below the fold.
        let row = app.buttons["Settings Row \(rowTitle)"].firstMatch
        var swipes = 0
        while !(row.existsOrWait(timeout: 1) && row.isHittable), swipes < 3 {
            app.swipeDown()
            swipes += 1
        }
        swipes = 0
        while !(row.existsOrWait(timeout: 1) && row.isHittable), swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(row.exists && row.isHittable, "Settings row \(rowTitle) should be hittable", file: file, line: line)
        row.tap()

        let title = screenTitle ?? rowTitle
        XCTAssertTrue(
            app.navigationBars[title].existsOrWait(timeout: 10),
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
        // Already there: re-tapping the tab would pop to the Library and
        // push All again, moving rows mid-assertion.
        if app.navigationBars["All Episodes"].exists, app.tabBars.buttons["Library"].isSelected {
            return
        }
        openSection("Library", in: app, file: file, line: line)
        // Switching back to the tab keeps its stack, which may already show
        // All; anything else pushed is popped by tapping the tab again.
        // Polls both outcomes briefly instead of waiting out either one.
        let allBar = app.navigationBars["All Episodes"]
        let allPlaylist = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "playlist-row-", "All Episodes"))
            .firstMatch
        let deadline = Date().addingTimeInterval(2)
        while !allBar.exists, !allPlaylist.exists, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if allBar.exists {
            return
        }
        if !allPlaylist.exists {
            openSection("Library", in: app, file: file, line: line)
        }
        XCTAssertTrue(allPlaylist.existsOrWait(timeout: 10), "All playlist should exist", file: file, line: line)
        allPlaylist.tap()
        XCTAssertTrue(
            app.navigationBars["All Episodes"].existsOrWait(timeout: 10),
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
        if tabButton.existsOrWait(timeout: 1), tabButton.isHittable {
            return tabButton
        }

        if let button = firstNonNavigationBarButton(title, in: app, timeout: 1) {
            return button
        }

        app.swipeDown()
        if tabButton.existsOrWait(timeout: 1), tabButton.isHittable {
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
        guard buttons.firstMatch.existsOrWait(timeout: timeout) else {
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
