import Foundation
import OpenCastCore
import OSLog

/// Fresh remote downloads run on a background `URLSession`, so one started
/// in a new-episode push wake, or one the listener leaves running, finishes
/// while the app is suspended. File URLs and resumed partials keep the
/// foreground downloader and its Range request; a pause of a background
/// download keeps no partial, so its resume starts over.
///
/// A download that finishes after its process ended has no caller waiting:
/// its file is left at `finishedFileURL(forTemporaryURL:)` beside the
/// temporary file it was meant for, and launch reconciliation completes the
/// download record from it.
nonisolated final class BackgroundEpisodeAudioDownloader: NSObject, EpisodeAudioDownloading, @unchecked Sendable {
    static let sessionIdentifier = "mk.lan.opencast.episode-downloads"
    @MainActor static let shared = BackgroundEpisodeAudioDownloader(foreground: URLSessionEpisodeAudioDownloader())

    private static let progressInterval: TimeInterval = 0.25
    private static let logger = Logger(subsystem: "mk.lan.opencast", category: "BackgroundDownloads")

    private struct Waiter {
        let continuation: CheckedContinuation<EpisodeDownloadResponseMetadata, any Error>
        let progress: @MainActor @Sendable (_ bytesReceived: Int64, _ bytesExpected: Int64?) -> Void
        var lastProgressAt: Date = .distantPast
        var metadata: EpisodeDownloadResponseMetadata?
        var error: (any Error)?
    }

    private let foreground: URLSessionEpisodeAudioDownloader
    private let lock = NSLock()
    private var waiters: [Int: Waiter] = [:]
    private var eventsCompletionHandler: (@MainActor @Sendable () -> Void)?
    private var orphanFinishedHandler: (@MainActor @Sendable () -> Void)?
    private var session: URLSession!

    private init(foreground: URLSessionEpisodeAudioDownloader) {
        self.foreground = foreground
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .utility
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }

    /// Where a download that finished with no caller waiting leaves its file.
    static func finishedFileURL(forTemporaryURL temporaryURL: URL) -> URL {
        temporaryURL.deletingPathExtension().appendingPathExtension("finished")
    }

    /// Told when a download with no caller waiting finishes while the app
    /// runs, so the store can adopt its file at once.
    func setOrphanFinishedHandler(_ handler: @escaping @MainActor @Sendable () -> Void) {
        lock.withLock { orphanFinishedHandler = handler }
    }

    func liveDetachedTemporaryPaths() async -> Set<String> {
        let tasks = await session.allTasks
        let waiting = lock.withLock { Set(waiters.keys) }
        return Set(tasks.compactMap { task in
            guard !waiting.contains(task.taskIdentifier),
                  task.state == .running || task.state == .suspended
            else {
                return nil
            }
            return task.taskDescription
        })
    }

    /// The app delegate hands over the system's completion handler when iOS
    /// launches or wakes the app for this session's events.
    func handleEvents(completionHandler: @escaping @MainActor @Sendable () -> Void) {
        lock.withLock { eventsCompletionHandler = completionHandler }
    }

    func download(
        from sourceURL: URL,
        to temporaryURL: URL,
        resume: EpisodeDownloadResumeContext?,
        onResponseMetadata: @escaping @MainActor @Sendable (EpisodeDownloadResponseMetadata) -> Void,
        progress: @escaping @MainActor @Sendable (_ bytesReceived: Int64, _ bytesExpected: Int64?) -> Void
    ) async throws {
        if sourceURL.isFileURL || (resume?.offset ?? 0) > 0 {
            try await foreground.download(
                from: sourceURL,
                to: temporaryURL,
                resume: resume,
                onResponseMetadata: onResponseMetadata,
                progress: progress
            )
            return
        }

        var request = URLRequest(url: sourceURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(OpenCastMediaRequestProfile.acceptEncoding, forHTTPHeaderField: "Accept-Encoding")
        request.setValue(OpenCastMediaRequestProfile.userAgent, forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        task.taskDescription = temporaryURL.path
        let taskID = task.taskIdentifier

        let metadata = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    waiters[taskID] = Waiter(continuation: continuation, progress: progress)
                }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        await onResponseMetadata(metadata)
    }

    private func resolve(taskID: Int, _ result: Result<EpisodeDownloadResponseMetadata, any Error>) {
        let waiter = lock.withLock { waiters.removeValue(forKey: taskID) }
        waiter?.continuation.resume(with: result)
    }
}

extension BackgroundEpisodeAudioDownloader: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = Date.now
        let progress: (@MainActor @Sendable (Int64, Int64?) -> Void)? = lock.withLock {
            guard var waiter = waiters[downloadTask.taskIdentifier],
                  now.timeIntervalSince(waiter.lastProgressAt) >= Self.progressInterval
            else {
                return nil
            }
            waiter.lastProgressAt = now
            waiters[downloadTask.taskIdentifier] = waiter
            return waiter.progress
        }
        guard let progress else {
            return
        }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        Task { @MainActor in
            progress(totalBytesWritten, expected)
        }
    }

    /// The file at `location` is gone once this returns, so it moves now:
    /// to the waiting caller's temporary file, or beside it as `.finished`.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskID = downloadTask.taskIdentifier
        let outcome: Result<EpisodeDownloadResponseMetadata, any Error>
        do {
            outcome = .success(try settle(downloadTask: downloadTask, location: location))
        } catch {
            outcome = .failure(error)
        }
        lock.withLock {
            guard waiters[taskID] != nil else {
                return
            }
            switch outcome {
            case .success(let metadata): waiters[taskID]?.metadata = metadata
            case .failure(let error): waiters[taskID]?.error = error
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let taskID = task.taskIdentifier
        let waiter = lock.withLock { waiters[taskID] }
        guard let waiter else {
            if let error {
                Self.logger.log("orphaned download failed: \(error.localizedDescription, privacy: .public)")
            }
            return
        }
        if let error {
            let isCancelled = (error as? URLError)?.code == .cancelled
            resolve(taskID: taskID, .failure(isCancelled ? CancellationError() : error))
        } else if let failure = waiter.error {
            resolve(taskID: taskID, .failure(failure))
        } else if let metadata = waiter.metadata {
            resolve(taskID: taskID, .success(metadata))
        } else {
            resolve(taskID: taskID, .failure(EpisodeDownloadError.interrupted))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = lock.withLock {
            defer { eventsCompletionHandler = nil }
            return eventsCompletionHandler
        }
        guard let handler else {
            return
        }
        Task { @MainActor in
            handler()
        }
    }

    private func settle(downloadTask: URLSessionDownloadTask, location: URL) throws -> EpisodeDownloadResponseMetadata {
        guard let response = downloadTask.response else {
            throw EpisodeDownloadError.interrupted
        }
        let normalized = OpenCastHTTPResponse(response)
        let statusCode = normalized.statusCode ?? -1
        guard (200..<300).contains(statusCode) else {
            throw EpisodeDownloadError.invalidHTTPStatus(statusCode)
        }
        if let contentEncoding = normalized.headerValue("content-encoding")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !contentEncoding.isEmpty,
           contentEncoding.caseInsensitiveCompare("identity") != .orderedSame {
            throw EpisodeDownloadError.unsupportedContentEncoding
        }
        guard let temporaryPath = downloadTask.taskDescription, !temporaryPath.isEmpty else {
            throw EpisodeDownloadError.invalidDownloadedRecord
        }
        let temporaryURL = URL(filePath: temporaryPath)
        let hasWaiter = lock.withLock { waiters[downloadTask.taskIdentifier] != nil }
        let destination = hasWaiter ? temporaryURL : Self.finishedFileURL(forTemporaryURL: temporaryURL)
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destination)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: location, to: destination)
        if !hasWaiter {
            Self.logger.log("orphaned download finished file=\(destination.lastPathComponent, privacy: .public)")
            if let handler = lock.withLock({ orphanFinishedHandler }) {
                Task { @MainActor in
                    handler()
                }
            }
        }
        return EpisodeDownloadResponseMetadata(
            entityTag: normalized.headerValue("etag"),
            lastModified: normalized.headerValue("last-modified"),
            // The normalized response drops the parsed filename, which
            // handles RFC 5987 `filename*=`.
            suggestedFilename: normalized.headerValue("content-disposition") == nil
                ? nil
                : response.suggestedFilename,
            mimeType: normalized.mimeType
        )
    }
}
