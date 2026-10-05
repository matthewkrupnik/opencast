import Foundation

nonisolated enum RemoteTranscriptionAppAttestKeychainServices {
    static let development = "mk.lan.opencast.remote-transcription-security.development"
    /// Retains the original service name so existing prod-staging installs do not
    /// unnecessarily attest a replacement key.
    static let prodStaging = "mk.lan.opencast.remote-transcription-security.production"
    /// The production money/state lane must never share an App Attest key
    /// with prod-staging.
    static let production = "mk.lan.opencast.remote-transcription-security.production-live"

    static let all = [
        development,
        prodStaging,
        production
    ]
}
