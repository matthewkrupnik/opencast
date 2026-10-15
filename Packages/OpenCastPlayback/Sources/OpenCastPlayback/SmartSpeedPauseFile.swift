import Foundation

/// The pauses found in a download, saved beside it as `<file>.smartspeed`.
/// Finding them decodes the whole file (seconds for a long episode);
/// building the trimmed copy from a saved list takes milliseconds, so later
/// plays and relaunches start trimmed.
nonisolated enum SmartSpeedPauseFile {
    /// Bump when detection changes, so older saves are found again.
    static let version = 1

    private struct Contents: Codable {
        let version: Int
        let fileIdentity: PlaybackLocalFileIdentity
        let analysis: SmartSpeedAnalysis
    }

    static func url(for audioURL: URL) -> URL {
        audioURL.appendingPathExtension("smartspeed")
    }

    static func exists(for audioURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: url(for: audioURL).path)
    }

    /// The saved pauses, if they were found in this exact file.
    static func load(for audioURL: URL) -> SmartSpeedAnalysis? {
        guard let identity = PlaybackLocalFileIdentity(at: audioURL),
              let data = try? Data(contentsOf: url(for: audioURL)),
              let contents = try? JSONDecoder().decode(Contents.self, from: data),
              contents.version == version,
              contents.fileIdentity == identity
        else {
            return nil
        }
        return contents.analysis
    }

    /// Finds the pauses and saves them for next time. A failed save only
    /// costs the next play another analysis.
    static func analyzeAndSave(for audioURL: URL) throws -> SmartSpeedAnalysis {
        let identity = PlaybackLocalFileIdentity(at: audioURL)
        let analysis = try SmartSpeedAnalyzer.analyze(url: audioURL)
        if let identity, identity == PlaybackLocalFileIdentity(at: audioURL) {
            let contents = Contents(version: version, fileIdentity: identity, analysis: analysis)
            try? JSONEncoder().encode(contents).write(to: url(for: audioURL), options: .atomic)
        }
        return analysis
    }

    @concurrent
    static func loadInBackground(for audioURL: URL) async -> SmartSpeedAnalysis? {
        load(for: audioURL)
    }

    @concurrent
    static func analyzeAndSaveInBackground(for audioURL: URL) async throws -> SmartSpeedAnalysis {
        try analyzeAndSave(for: audioURL)
    }
}

/// Finds a download's pauses ahead of its first Smart Speed play, one file
/// at a time so a batch of finished downloads does not decode in parallel.
public actor SmartSpeedPausePreparer {
    public static let shared = SmartSpeedPausePreparer()

    public func preparePauses(for fileURL: URL) {
        guard fileURL.isFileURL, SmartSpeedPauseFile.load(for: fileURL) == nil else {
            return
        }
        _ = try? SmartSpeedPauseFile.analyzeAndSave(for: fileURL)
    }

    /// The saved pauses beside a download, for removal along with it.
    public nonisolated static func pauseFileURL(for audioURL: URL) -> URL {
        SmartSpeedPauseFile.url(for: audioURL)
    }
}
