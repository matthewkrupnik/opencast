@preconcurrency import AVFoundation
import Foundation

struct PlaybackFailureRecoveryPolicy {
    static let automaticTransientFailureRetryLimit = 1
    /// `AVError.Code.mediaServicesWereReset`, which the macOS SDK lacks.
    static let mediaServicesWereResetErrorCode = -11819

    private(set) var automaticTransientFailureRetryCount = 0

    mutating func reset() {
        automaticTransientFailureRetryCount = 0
    }

    mutating func shouldAttemptAutomaticRetry(
        error: (any Error)?,
        errorLog: AVPlayerItemErrorLog?
    ) -> Bool {
        guard automaticTransientFailureRetryCount < Self.automaticTransientFailureRetryLimit,
              Self.isTransientTimeout(error: error, errorLog: errorLog)
        else {
            return false
        }

        automaticTransientFailureRetryCount += 1
        return true
    }

    /// The media server restarted under the item. Every AVPlayer created
    /// before the restart stays unusable, so retrying on it never recovers.
    static func isMediaServicesReset(_ error: (any Error)?) -> Bool {
        guard let error else {
            return false
        }

        let nsError = error as NSError
        if nsError.domain == AVFoundationErrorDomain,
           nsError.code == mediaServicesWereResetErrorCode
        {
            return true
        }

        return isMediaServicesReset(nsError.userInfo[NSUnderlyingErrorKey] as? any Error)
    }

    static func errorLogFieldsIndicateTimedOut(
        errorDomain: String,
        errorStatusCode: Int,
        errorComment: String?
    ) -> Bool {
        if errorDomain == NSURLErrorDomain, errorStatusCode == NSURLErrorTimedOut {
            return true
        }

        return errorComment?.localizedCaseInsensitiveContains("timed out") == true
    }

    private static func isTransientTimeout(
        error: (any Error)?,
        errorLog: AVPlayerItemErrorLog? = nil
    ) -> Bool {
        errorChainContainsTimedOut(error)
            || errorLog?.events.contains(where: errorLogEventIsTimedOut) == true
    }

    private static func errorChainContainsTimedOut(_ error: (any Error)?) -> Bool {
        guard let error else {
            return false
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
            return true
        }
        if nsError.localizedDescription.localizedCaseInsensitiveContains("timed out") {
            return true
        }

        return errorChainContainsTimedOut(nsError.userInfo[NSUnderlyingErrorKey] as? any Error)
    }

    private static func errorLogEventIsTimedOut(_ event: AVPlayerItemErrorLogEvent) -> Bool {
        errorLogFieldsIndicateTimedOut(
            errorDomain: event.errorDomain,
            errorStatusCode: event.errorStatusCode,
            errorComment: event.errorComment
        )
    }
}
