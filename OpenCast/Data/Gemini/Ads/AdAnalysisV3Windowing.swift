import Foundation

/// Port of the worker's `v3_windowing.rs`: local-attention windows of 800
/// segments overlapping by 120, run at most four at a time. Engines with a
/// smaller context pass their own window size.
nonisolated enum AdAnalysisV3Windowing {
    static let windowSegments = 800
    static let overlapSegments = 120
    static let concurrentWindows = 4

    static func windowCount(
        _ segmentCount: Int,
        size: Int = windowSegments,
        overlap: Int = overlapSegments
    ) -> Int {
        let excess = max(0, segmentCount - size)
        let stride = size - overlap
        return 1 + (excess + stride - 1) / stride
    }

    static func windows(
        _ request: EpisodeAdAnalysisAPIRequest,
        size: Int = windowSegments,
        overlap: Int = overlapSegments
    ) -> [EpisodeAdAnalysisAPIRequest] {
        (0..<windowCount(request.segments.count, size: size, overlap: overlap)).map { index in
            let start = index * (size - overlap)
            let end = min(start + size, request.segments.count)
            var window = request
            window.segments = Array(request.segments[start..<end])
            window.transcript.segmentCount = window.segments.count
            return window
        }
    }
}
