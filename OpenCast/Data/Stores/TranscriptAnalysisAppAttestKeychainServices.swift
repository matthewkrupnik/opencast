import Foundation

nonisolated enum TranscriptAnalysisAppAttestKeychainServices {
    static let development = "mk.lan.opencast.transcript-analysis-security.development"
    static let prodStaging = "mk.lan.opencast.transcript-analysis-security.prod-staging"
    static let production = "mk.lan.opencast.transcript-analysis-security.production"

    static let all = [
        development,
        prodStaging,
        production
    ]
}
