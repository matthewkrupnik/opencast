import Foundation

enum TranscriptionFailureClassification: Equatable {
    case cancelled
    case environmentalCompute
    case environmentalStorage
    case environmentalSuspension
    case failed
}

struct TranscriptionFailureClassifier {
    static func classify(
        _ error: any Error,
        environment: EpisodeTranscriptionFailureEnvironment
    ) -> TranscriptionFailureClassification {
        if error is CancellationError {
            return .cancelled
        }

        let nsError = error as NSError
        if isCancellation(nsError) {
            return .cancelled
        }

        // Whisper-perf G2: the audio spill makes disk headroom a runtime
        // dependency; exhaustion is environmental in any scene state — the
        // episode must interrupt (resumable), not fail terminally.
        if isStorageExhaustion(nsError) {
            return .environmentalStorage
        }

        // An app suspended mid-decode resumes to find the out-of-process
        // audio converter timed out; the audio itself is fine, so the
        // episode must interrupt (resumable), not fail terminally.
        if isAudioDecoderTimeout(nsError) {
            return .environmentalSuspension
        }

        guard environment.isConstrained,
              isComputeDomain(nsError.domain)
        else {
            return .failed
        }

        return .environmentalCompute
    }

    private static func isStorageExhaustion(_ error: NSError) -> Bool {
        switch (error.domain, error.code) {
        case (NSCocoaErrorDomain, CocoaError.Code.fileWriteOutOfSpace.rawValue),
             (NSPOSIXErrorDomain, Int(POSIXErrorCode.ENOSPC.rawValue)):
            return true
        default:
            break
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isStorageExhaustion(underlying)
        }
        return false
    }

    /// AVAudioFile's read error for the converter's '!tim' timeout.
    private static func isAudioDecoderTimeout(_ error: NSError) -> Bool {
        error.domain == "com.apple.coreaudio.avfaudio" && error.code == 0x2174_696D
    }

    private static func isCancellation(_ error: NSError) -> Bool {
        switch (error.domain, error.code) {
        case (NSURLErrorDomain, NSURLErrorCancelled),
             (NSCocoaErrorDomain, CocoaError.Code.userCancelled.rawValue),
             (NSPOSIXErrorDomain, Int(POSIXErrorCode.ECANCELED.rawValue)):
            true
        default:
            false
        }
    }

    private static func isComputeDomain(_ domain: String) -> Bool {
        [
            "com.apple.CoreML",
            "com.apple.Espresso",
            "com.apple.espresso",
            "com.apple.appleneuralengine",
            "com.apple.MetalPerformanceShadersGraph"
        ].contains(domain)
    }
}
