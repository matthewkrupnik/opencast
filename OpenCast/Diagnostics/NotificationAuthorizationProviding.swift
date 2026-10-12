import UserNotifications

protocol NotificationAuthorizationProviding {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> UNAuthorizationStatus
}

extension NotificationAuthorizationService: NotificationAuthorizationProviding {}
