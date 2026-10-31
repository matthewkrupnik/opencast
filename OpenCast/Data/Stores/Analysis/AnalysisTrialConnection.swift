import Foundation
import OpenCastAnalysisProviders

/// This build has no trial service: outside UI tests there is no trial
/// route, and runs without the listener's key use the built-in key. Under
/// UI testing it answers the seeded status and never touches the network.
nonisolated final class AnalysisTrialConnection: AnalysisTrialConnecting {
    /// UI tests: the seeded status, answered without a request.
    private let fixtureStatus: AnalysisTrialProxyStatus?
    private let isFixture: Bool

    init(fixtureStatus: AnalysisTrialProxyStatus? = nil, isFixture: Bool = false) {
        self.fixtureStatus = fixtureStatus
        self.isFixture = isFixture
    }

    var isConfigured: Bool {
        isFixture
    }

    func exchange(trialEndpoint: URL) async -> (any AnalysisTrialProxyExchange)? {
        isFixture ? AnalysisUITestTrialProxyExchange() : nil
    }

    func fetchStatus(trialEndpoint: URL) async -> AnalysisTrialProxyStatus? {
        isFixture ? fixtureStatus : nil
    }
}

/// UI tests route trial runs through the fixture transport; this exchange
/// only stands in for the route and is never posted to.
nonisolated struct AnalysisUITestTrialProxyExchange: AnalysisTrialProxyExchange {
    func post(
        path: String,
        payloadText: String,
        timeoutSeconds: Double,
        maximumBodyBytes: Int
    ) async throws(AnalysisHTTPFailure) -> AnalysisHTTPResponse {
        throw .network
    }
}
