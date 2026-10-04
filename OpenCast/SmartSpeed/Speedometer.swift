import Foundation

final class Speedometer: @unchecked Sendable {
    private var lastReal: TimeInterval?
    private var lastMedia: Double?
    private(set) var secondsSaved: Double = 0

    func update(mediaSeconds: Double, realSeconds: TimeInterval) {
        defer {
            lastMedia = mediaSeconds
            lastReal = realSeconds
        }
        
        guard let lr = lastReal, let lm = lastMedia else { return }
        
        let mediaDelta = mediaSeconds - lm
        let realDelta = realSeconds - lr
        
        // Only count positive savings (playing faster than realtime)
        if mediaDelta > realDelta {
            secondsSaved += (mediaDelta - realDelta)
        }
    }
}