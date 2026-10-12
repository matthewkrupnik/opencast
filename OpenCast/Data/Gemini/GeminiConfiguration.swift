import Foundation

/// Where the app's Gemini calls go and with which key. The key is a build
/// setting (`GEMINI_API_KEY`, from the git-ignored `Config/Secrets.xcconfig`)
/// surfaced through Info.plist; blank means the features report themselves
/// unavailable.
nonisolated struct GeminiConfiguration: Sendable, Equatable {
    static let infoPlistKey = "OpenCastGeminiAPIKey"
    static let defaultBaseURL = URL(string: "https://generativelanguage.googleapis.com")!
    static let missingKeyMessage =
        "Gemini API key not configured. Set GEMINI_API_KEY in Config/Secrets.xcconfig and rebuild."

    var apiKey: String?
    var baseURL: URL

    init(apiKey: String?, baseURL: URL = Self.defaultBaseURL) {
        self.apiKey = Self.normalizedKey(apiKey)
        self.baseURL = baseURL
    }

    static var current: GeminiConfiguration {
        let bundledKey = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let baseURL = environment["OPENCAST_GEMINI_BASE_URL"].flatMap(URL.init(string:)) ?? defaultBaseURL
        return GeminiConfiguration(apiKey: environment["OPENCAST_GEMINI_API_KEY"] ?? bundledKey, baseURL: baseURL)
        #else
        return GeminiConfiguration(apiKey: bundledKey)
        #endif
    }

    var unavailableMessage: String? {
        apiKey == nil ? Self.missingKeyMessage : nil
    }

    private static func normalizedKey(_ key: String?) -> String? {
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty,
              !key.hasPrefix("$(")
        else {
            return nil
        }
        return key
    }
}
