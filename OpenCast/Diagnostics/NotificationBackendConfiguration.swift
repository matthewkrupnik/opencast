import Foundation

/// The self-hosted NotificationsWorker this build registers with. The host
/// (and optional path) is a build setting (`NOTIFICATIONS_WORKER`, set in
/// the git-ignored `Config/Secrets.xcconfig`) surfaced through Info.plist;
/// blank means no worker, and new-episode notifications stay on device.
nonisolated struct NotificationBackendConfiguration: Sendable {
    static let infoPlistKey = "OpenCastNotificationsWorker"

    /// Nil when no worker is configured.
    let workerBaseURL: URL?
    let apnsEnvironment: String
    let keychainService: String

    var isConfigured: Bool {
        workerBaseURL != nil
    }

    /// The configured worker, or a placeholder that is never contacted while
    /// `isConfigured` is false.
    var resolvedWorkerBaseURL: URL {
        workerBaseURL ?? URL(string: "https://notifications.invalid")!
    }

    nonisolated static let current: Self = {
        let workerBaseURL = workerURL(
            from: Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String
        )
        #if INTERNAL_NOTIFICATIONS_DIAGNOSTICS
        return Self(
            workerBaseURL: workerBaseURL,
            apnsEnvironment: "production",
            keychainService: "mk.lan.opencast.notification-security.prod-staging"
        )
        #elseif DEBUG
        return Self(
            workerBaseURL: workerBaseURL,
            apnsEnvironment: "development",
            keychainService: "mk.lan.opencast.notification-security.development"
        )
        #else
        return Self(
            workerBaseURL: workerBaseURL,
            apnsEnvironment: "production",
            keychainService: "mk.lan.opencast.notification-security.production"
        )
        #endif
    }()

    /// xcconfig treats "//" as a comment, so the setting carries the host and
    /// optional path without a scheme; a full https URL is accepted too.
    static func workerURL(from setting: String?) -> URL? {
        guard var value = setting?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.hasPrefix("$(")
        else {
            return nil
        }
        if !value.lowercased().hasPrefix("https://") {
            value = "https://" + value
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        guard let url = URL(string: value), url.host() != nil else {
            return nil
        }
        return url
    }
}
