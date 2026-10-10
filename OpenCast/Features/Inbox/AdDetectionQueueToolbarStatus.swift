import SwiftUI

/// Reads the ad-detection queue snapshot in its own body so per-stage queue
/// churn (transcription progress publishes many stage updates per episode)
/// re-evaluates this indicator alone, never the collection it sits above.
struct AdDetectionQueueToolbarStatus: View {
    @Environment(OpenCastAppModel.self) private var appModel

    let onOpen: () -> Void

    var body: some View {
        let presentation = AdDetectionQueuePresentation(
            snapshot: appModel.adFreePass.queueSnapshot,
            isBackgroundSessionArmed: appModel.adFreePassBackgroundSession.isArmed
        )
        AdDetectionQueueToolbarIndicator(
            indicator: presentation.indicator,
            accessibilityValue: presentation.accessibilityValue,
            onOpen: onOpen
        )
    }
}
