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

    /// The grids' row spacing for a width class, which is also the shell's
    /// row gap above the tab accessory for screens whose rows abut.
    static func rowSpacing(isCompact: Bool) -> Double {
        Self(isCompact: isCompact, isAccessibilitySize: false).rowSpacing
    }

    /// Kept only for `TabAccessoryGeometryTests`; it goes with them.
    static func resolve(containerWidth _: Double, isCompact: Bool, isAccessibilitySize: Bool) -> Self {
        Self(isCompact: isCompact, isAccessibilitySize: isAccessibilitySize)
    }

    var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minimumTileWidth), spacing: columnSpacing, alignment: .top)]
    }
}
