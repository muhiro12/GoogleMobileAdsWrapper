import CoreGraphics

/// Fixed design dimensions of the native ad layout, on an eight-point grid.
///
/// System text styles, button metrics, measured text, creative aspect ratios,
/// and Google's minimum asset sizes are not part of this grid.
enum NativeAdMetrics {
    static let gridUnit: CGFloat = 8

    /// Spacing between assets and between lines of the text column.
    static let spacing = gridUnit
    static let iconSize = gridUnit * 5
    static let iconCornerRadius = gridUnit
    /// The trailing space left clear for the SDK's AdChoices overlay.
    static let adChoicesInset = gridUnit * 4
    /// The narrowest text column that keeps the compact call to action in the row.
    static let minimumRowTextWidth = gridUnit * 18
    /// Narrower placements cannot present the required assets and stay empty.
    static let minimumWidth = gridUnit * 20
    /// The width used when SwiftUI proposes no specific width.
    static let idealWidth = gridUnit * 40
    /// The lower bound of the media region's height limit, which keeps a 16:9
    /// creative unletterboxed at the ideal width.
    static let mediaHeightLimitBaseline = gridUnit * 23
    static let maximumMediaHeight = gridUnit * 40

    static let badgeMinimumWidth = gridUnit * 4
    /// Google requires attribution of at least 15 points in each dimension.
    static let badgeMinimumHeight = gridUnit * 2
    static let badgeHorizontalPadding = gridUnit
    static let badgeCornerRadius = gridUnit
}
