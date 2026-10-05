import AVFoundation

nonisolated final class PCMDecoder: @unchecked Sendable {
    let file: AVAudioFile
    let format: AVAudioFormat
    private let queue = DispatchQueue(label: "smart-speed.decoder", qos: .userInitiated)
    private var readFrame: AVAudioFramePosition = 0

    init(url: URL) throws {
        file = try AVAudioFile(forReading: url)
        format = file.processingFormat
        file.framePosition = 0
    }
    
    var fileLength: AVAudioFramePosition {
        return file.length
    }

    /// Reads up to maxFrames into an (already sized) buffer. Returns true if more data remains.
    func read(into buffer: AVAudioPCMBuffer, maxFrames: AVAudioFrameCount) -> Bool {
        try? file.read(into: buffer, frameCount: maxFrames)
        return file.framePosition < file.length
    }

    func seek(toFrame f: AVAudioFramePosition) {
        file.framePosition = f
        readFrame = f
    }
}