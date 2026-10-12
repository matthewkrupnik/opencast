/// Client-side gates for Chapters & Summary capabilities that ship dark.
/// Each flag both enables its behavior and admits its sentence into the
/// generate disclosure — the dialog must never claim something that isn't
/// live.
enum TranscriptAnalysisFeatureFlags {
    /// Cross-user result sharing (`SHARED_RESULTS_ENABLED` on the worker).
    /// While false the client sends `allow_shared: false` on every request.
    nonisolated static let isSharingEnabled = false
}
