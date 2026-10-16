import CoreGraphics

struct SafeAreaInsets: Equatable {
    var top: CGFloat
    var right: CGFloat
    var bottom: CGFloat
    var left: CGFloat
}

extension SafeAreaInsets {
    /// Both frames use AppKit global coordinates, with the y-axis pointing up.
    static func compute(screenFrame: CGRect, visibleFrame: CGRect) -> SafeAreaInsets {
        SafeAreaInsets(
            top: max(0, screenFrame.maxY - visibleFrame.maxY),
            right: max(0, screenFrame.maxX - visibleFrame.maxX),
            bottom: max(0, visibleFrame.minY - screenFrame.minY),
            left: max(0, visibleFrame.minX - screenFrame.minX)
        )
    }
}
