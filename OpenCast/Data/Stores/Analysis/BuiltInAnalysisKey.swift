import Foundation
import OpenCastAnalysis
import OpenCastAnalysisProviders

/// This build's own Gemini key: the build setting `GEMINI_API_KEY` (from the
/// git-ignored `Config/Secrets.xcconfig`) surfaced through Info.plist. Runs
/// use it when the listener has saved no key of their own; blank means
/// there is none and those runs show the key screen.
nonisolated enum BuiltInAnalysisKey {
    static let infoPlistKey = "OpenCastGeminiAPIKey"
    static let environmentKey = "OPENCAST_GEMINI_API_KEY"

    static var google: AnalysisProviderKey? {
        var value = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String
        #if DEBUG
        value = ProcessInfo.processInfo.environment[environmentKey] ?? value
        #endif
        guard let value, !value.hasPrefix("$(") else {
            return nil
        }
        return AnalysisProviderKey(value)
    }
}

/// The listener's saved keys, with the built-in Google key standing in when
/// no Google key is saved, so a run on the built-in key passes the same
/// key-presence checks as a run on a saved one. Writes go to the Keychain.
nonisolated struct BuiltInKeyFallbackStorage: AnalysisProviderKeyStoring {
    let inner: any AnalysisProviderKeyStoring
    let builtInGoogleKey: AnalysisProviderKey

    func key(for provider: AnalysisProvider) throws(AnalysisProviderKeyStoreError) -> AnalysisProviderKey? {
        if let key = try inner.key(for: provider) {
            return key
        }
        return provider == .google ? builtInGoogleKey : nil
    }

    func save(_ key: AnalysisProviderKey, provider: AnalysisProvider, syncs: Bool) throws(AnalysisProviderKeyStoreError) {
        try inner.save(key, provider: provider, syncs: syncs)
    }

    func remove(provider: AnalysisProvider, includingSyncedCopy: Bool) throws(AnalysisProviderKeyStoreError) {
        try inner.remove(provider: provider, includingSyncedCopy: includingSyncedCopy)
    }

    func setSyncs(_ syncs: Bool, provider: AnalysisProvider) throws(AnalysisProviderKeyStoreError) {
        try inner.setSyncs(syncs, provider: provider)
    }

    func removeSyncedCopy(provider: AnalysisProvider) throws(AnalysisProviderKeyStoreError) {
        try inner.removeSyncedCopy(provider: provider)
    }

    func presence(for provider: AnalysisProvider) throws(AnalysisProviderKeyStoreError) -> AnalysisKeyPresence {
        try inner.presence(for: provider)
    }

    func syncedCopyExists(for provider: AnalysisProvider) throws(AnalysisProviderKeyStoreError) -> Bool {
        try inner.syncedCopyExists(for: provider)
    }
}
