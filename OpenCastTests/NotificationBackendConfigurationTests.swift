import Testing
@testable import OpenCast

struct NotificationBackendConfigurationTests {
    @Test(
        "The NOTIFICATIONS_WORKER setting becomes an https base URL, and blank or unexpanded means no worker",
        arguments: [
            ("notifications.example.com/development/", "https://notifications.example.com/development"),
            ("https://notifications.example.com", "https://notifications.example.com"),
            ("  ", nil),
            ("$(NOTIFICATIONS_WORKER)", nil),
        ] as [(String, String?)]
    )
    func workerSettingParsing(setting: String, expected: String?) {
        #expect(NotificationBackendConfiguration.workerURL(from: setting)?.absoluteString == expected)
    }
}
