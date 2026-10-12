import Foundation

typealias OpenCastRemoteModelDownloadProgressHandler = @Sendable (_ bytesReceived: Int64) -> Void

protocol OpenCastRemoteModelTransport: Sendable {
    func download(
        from url: URL,
        to destinationURL: URL,
        expectedByteCount: Int64,
        maximumByteCount: Int64,
        progress: OpenCastRemoteModelDownloadProgressHandler?
    ) async throws -> OpenCastRemoteModelResponse
}
