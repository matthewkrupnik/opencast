import XCTest

final class NotificationSecurityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPhysicalDeviceNotificationLookFixtureScreenshots() throws {
        try skipIfRunningOnSimulator()

        let permissionMonitor = addUIInterruptionMonitor(withDescription: "Notification Permission") { alert in
            for buttonTitle in ["Allow", "Allow Notifications"] {
                let button = alert.buttons[buttonTitle]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        defer { removeUIInterruptionMonitor(permissionMonitor) }

        let app = XCUIApplication()
        app.launchArguments += [
            "--opencast-ui-testing",
            "--opencast-force-light-mode",
            "--opencast-schedule-notification-look-fixture",
        ]
        app.launchEnvironment["OPENCAST_UI_TESTING"] = "1"
        app.launchEnvironment["OPENCAST_FORCE_LIGHT_MODE"] = "1"
        app.launchEnvironment["OPENCAST_SCHEDULE_NOTIFICATION_LOOK_FIXTURE"] = "1"
        app.launch()
        app.tap()

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        Thread.sleep(forTimeInterval: 5)
        settleSpringBoardNotificationSurface(in: springboard)
        let notification = try waitForSpringBoardNotification(
            containing: "866: Very Nice",
            in: springboard,
            timeout: 30
        )
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 2))
        attachSmokeScreenshot(named: "notification_look_collapsed")

        notification.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 2))
        attachSmokeScreenshot(named: "notification_look_expanded")
    }

    @MainActor
    func testSimulatorAdFreePassCompletionNotificationLookFixtureScreenshots() throws {
        let permissionMonitor = addUIInterruptionMonitor(withDescription: "Notification Permission") { alert in
            for buttonTitle in ["Allow", "Allow Notifications"] {
                let button = alert.buttons[buttonTitle]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        defer { removeUIInterruptionMonitor(permissionMonitor) }

        let app = XCUIApplication()
        app.launchArguments += [
            "--opencast-ui-testing",
            "--opencast-force-light-mode",
            "--opencast-schedule-adfreepass-notification-look-fixture",
        ]
        app.launchEnvironment["OPENCAST_UI_TESTING"] = "1"
        app.launchEnvironment["OPENCAST_FORCE_LIGHT_MODE"] = "1"
        app.launchEnvironment["OPENCAST_SCHEDULE_ADFREEPASS_NOTIFICATION_LOOK_FIXTURE"] = "1"
        app.launch()
        app.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow"]
        if allowButton.existsOrWait(timeout: 5) {
            allowButton.tap()
        }

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5)
        settleSpringBoardNotificationSurface(in: springboard)
        let notification = try waitForSpringBoardNotification(
            containing: "ad breaks",
            in: springboard,
            timeout: 30
        )
        XCTAssertTrue(notification.exists)
        XCTAssertNotEqual(app.state, .runningForeground)
        attachSmokeScreenshot(named: "adfreepass_notification_look_collapsed")

        notification.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(
            staticText(containing: "couldn't be analyzed", in: springboard).existsOrWait(timeout: 5),
            "Expanded ad-free-pass notification should render the failures body line."
        )
        XCTAssertNotEqual(app.state, .runningForeground)
        attachSmokeScreenshot(named: "adfreepass_notification_look_expanded")
    }

    private func skipIfRunningOnSimulator() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Production App Attest/APNs notification diagnostics require a physical device.")
        #endif
    }

    @MainActor
    private func staticText(containing label: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", label)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }
}
