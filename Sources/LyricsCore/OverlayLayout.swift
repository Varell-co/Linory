import Foundation
import CoreGraphics

public enum OverlayLayout {
    /// Keep dimensions in points for readability; align the frame to the display's physical pixels.
    public static func frame(preferredSize: CGSize, currentFrame: CGRect, visibleFrame: CGRect, backingScale: CGFloat) -> CGRect {
        let margin = min(16, min(visibleFrame.width, visibleFrame.height) / 4)
        let area = visibleFrame.insetBy(dx: margin, dy: margin)
        let size = CGSize(
            width: (min(preferredSize.width, area.width) * backingScale).rounded(.down) / backingScale,
            height: (min(preferredSize.height, area.height) * backingScale).rounded(.down) / backingScale)
        // Resizing keeps the top edge and, when snapped there, the right edge in place.
        let rightAligned = abs(currentFrame.maxX - area.maxX) < 1 / backingScale
        let x = rightAligned ? area.maxX - size.width : currentFrame.minX
        let y = currentFrame.maxY - size.height
        return CGRect(
            x: min(max((x * backingScale).rounded() / backingScale, area.minX), area.maxX - size.width),
            y: min(max((y * backingScale).rounded() / backingScale, area.minY), area.maxY - size.height),
            width: size.width, height: size.height)
    }
}
