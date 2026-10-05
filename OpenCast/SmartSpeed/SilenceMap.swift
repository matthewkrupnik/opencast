import AVFoundation

nonisolated final class SilenceMap: @unchecked Sendable {
    private let lock = NSLock()
    private var regions: [SilenceRegion] = []

    func replace(_ new: [SilenceRegion]) {
        lock.lock()
        regions = new
        lock.unlock()
    }
    
    func append(_ newRegions: [SilenceRegion]) {
        lock.lock()
        regions.append(contentsOf: newRegions)
        // Keep memory bounded in long streams (e.g. keep last N regions or prune those before playhead)
        // In a complete app, we'd prune older regions to avoid unbounded growth.
        lock.unlock()
    }

    func isSilence(atFrame f: AVAudioFramePosition) -> Bool {
        lock.lock(); defer { lock.unlock() }
        // Binary search
        var lo = 0
        var hi = regions.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let r = regions[mid]
            if f >= r.startFrame && f < r.endFrame {
                return true
            }
            if f < r.startFrame {
                hi = mid - 1
            } else {
                lo = mid + 1
            }
        }
        return false
    }

    func nearestSilenceEnd(before f: AVAudioFramePosition) -> AVAudioFramePosition? {
        lock.lock(); defer { lock.unlock() }
        for r in regions.reversed() where r.endFrame <= f {
            return r.startFrame
        }
        return nil
    }
}