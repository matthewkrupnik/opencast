import Foundation

/// Port of the worker's `v3_windowing.rs`: local-attention windows of 800
/// segments overlapping by 120, run at most four at a time.
nonisolated enum AdAnalysisV3Windowing {
    static let windowSegments = 800
    static let overlapSegments = 120
    static let concurrentWindows = 4

    static func windowCount(_ segmentCount: Int) -> Int {
        let excess = max(0, segmentCount - windowSegments)
        let stride = windowSegments - overlapSegments
        return 1 + (excess + stride - 1) / stride
    }

    static func windows(_ request: EpisodeAdAnalysisAPIRequest) -> [EpisodeAdAnalysisAPIRequest] {
        (0..<windowCount(request.segments.count)).map { index in
            let start = index * (windowSegments - overlapSegments)
            let end = min(start + windowSegments, request.segments.count)
            var window = request
            window.segments = Array(request.segments[start..<end])
            window.transcript.segmentCount = window.segments.count
            return window
        }
    }
}
