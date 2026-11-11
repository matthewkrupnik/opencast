import SwiftUI

/// The Library grids' adaptive columns and spacing for a width class.
/// Compact (phone-like) grids use smaller tiles; accessibility text sizes
/// raise the minimum tile width so titles keep room.
nonisolated struct LibraryGridMetrics: Equatable {
    let minimumTileWidth: Double
    let columnSpacing: Double
    let rowSpacing: Double
    let horizontalMargin: Double
    let isCompact: Bool

    init(isCompact: Bool, isAccessibilitySize: Bool) {
        self.isCompact = isCompact
        if isCompact {
            minimumTileWidth = isAccessibilitySize ? 150 : 100
            columnSpacing = 12
            rowSpacing = 18
            horizontalMargin = 20
        } else {
            minimumTileWidth = isAccessibilitySize ? 240 : 160
            columnSpacing = 16
            rowSpacing = 24
            horizontalMargin = 24
        }
    }

    var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minimumTileWidth), spacing: columnSpacing, alignment: .top)]
    }
}
