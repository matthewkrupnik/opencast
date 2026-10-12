/// Disclosure copy for the first-ever Generate Chapters & Summary tap. With
/// the per-show opt-in retired, this one-time dialog is the only place the
/// transcript-upload disclosure appears, so it must run before the first
/// generation. One of its sentences describes a flag-gated feature, so the
/// body is composed — that sentence appears only while its feature is live.
enum TranscriptAnalysisGenerateDisclosureCopy {
    nonisolated static let title = "Generate Chapters & Summary?"
    nonisolated static let confirmButtonTitle = "Generate"

    nonisolated static func confirmationBody(
        isSharingEnabled: Bool = TranscriptAnalysisFeatureFlags.isSharingEnabled
    ) -> String {
        var lines = [
            "This episode’s transcript is sent to OpenCast to generate chapters and a summary. Your audio is never sent.",
            "Results are saved on this device."
        ]
        if isSharingEnabled {
            lines.append("Chapters may be shared with other listeners of the same episode.")
        }
        return lines.joined(separator: "\n")
    }
}
