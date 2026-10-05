import Foundation

nonisolated enum AdAnalysisAppAttestKeychainServices {
    static let development = "mk.lan.opencast.ad-analysis-security.development"
    static let prodStaging = "mk.lan.opencast.ad-analysis-security.prod-staging"
    static let production = "mk.lan.opencast.ad-analysis-security.production"

    static let all = [
        development,
        prodStaging,
        production
    ]
}
