import Foundation
@testable import OpenCastTranscription

final class DictionaryRemoteModelTransport: OpenCastRemoteModelTransport, @unchecked Sendable {
    private let downloadBodies: [URL: Data]

    init(downloadBodies: [URL: Data] = [:]) {
        self.downloadBodies = downloadBodies
    }

    func download(
        from url: URL,
        to destinationURL: URL,
        expectedByteCount: Int64,
        maximumByteCount: Int64,
        progress: OpenCastRemoteModelDownloadProgressHandler?
    ) async throws -> OpenCastRemoteModelResponse {
        guard let data = downloadBodies[url] else {
            return OpenCastRemoteModelResponse(statusCode: 404)
        }
        let byteCount = Int64(data.count)
        guard byteCount <= expectedByteCount,
              byteCount <= maximumByteCount else {
            throw OpenCastTranscriptionError.invalidRemoteManifest(
                "downloaded byte count for \(url.absoluteString) exceeded configured limits"
            )
        }
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destinationURL)
        progress?(byteCount)
        return OpenCastRemoteModelResponse(statusCode: 200)
    }
}
