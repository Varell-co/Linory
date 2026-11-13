import AppKit
import SwiftUI

/// Linory brand tokens and marks (Brand Identity Kit v1.0). The marks are drawn from the kit's SVG paths,
/// so they work without a resource bundle (`swift run`) and stay sharp at any size.
enum Brand {
    static let name = "Linory"
    static let ink = Color(red: 20/255, green: 22/255, blue: 27/255)
    static let waveBlue = Color(red: 67/255, green: 133/255, blue: 239/255)
    static let waveLight = Color(red: 175/255, green: 201/255, blue: 241/255)
    static let accent = Color(red: 177/255, green: 197/255, blue: 229/255)
    static let panelCornerRadius: CGFloat = 20

    /// Monochrome template glyph for the status item; macOS tints it for light, dark and highlighted states.
    static let menuBarImage: NSImage = {
        let size = NSSize(width: 20, height: 17) // kit artboard 112×96
        let image = NSImage(size: size, flipped: true) { rect in
            let scale = rect.width / 112
            let transform = AffineTransform(scale: scale)
            NSColor.black.setFill()
            for path in [
                wave(start: (24, 42), (35, 25, 45, 26, 60, 34), (76, 43, 87, 46, 99, 33), (96, 47, 81, 57, 66, 49), (50, 40, 39, 33, 24, 42)),
                wave(start: (8, 65), (20, 46, 33, 45, 48, 54), (65, 64, 77, 67, 91, 54), (87, 70, 72, 78, 58, 70), (37, 59, 24, 55, 8, 65)),
            ] {
                path.transform(using: transform)
                path.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = name
        return image
    }()

    private typealias Curve = (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
    private static func wave(start: (CGFloat, CGFloat), _ curves: Curve...) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: start.0, y: start.1))
        for c in curves {
            path.curve(to: NSPoint(x: c.4, y: c.5), controlPoint1: NSPoint(x: c.0, y: c.1), controlPoint2: NSPoint(x: c.2, y: c.3))
        }
        path.close()
        return path
    }
}

/// The two-ribbon Linory symbol with its gradients, for the overlay header and Settings.
struct LinorySymbol: View {
    var body: some View {
        ZStack {
            WaveShape(start: (57, 78), curves: [(80, 48, 100, 45, 121, 49), (160, 61, 175, 95, 224, 50), (215, 87, 186, 108, 160, 94), (125, 77, 102, 52, 57, 78)])
                .fill(LinearGradient(stops: [
                    .init(color: Color(red: 175/255, green: 201/255, blue: 241/255), location: 0),
                    .init(color: Color(red: 128/255, green: 168/255, blue: 233/255), location: 0.47),
                    .init(color: Color(red: 82/255, green: 124/255, blue: 205/255), location: 1),
                ], startPoint: UnitPoint(x: 0, y: 0.2), endPoint: UnitPoint(x: 1, y: 0.9)))
            WaveShape(start: (15, 134), curves: [(39, 92, 67, 91, 95, 101), (132, 115, 156, 140, 204, 112), (193, 147, 168, 163, 132, 148), (93, 130, 59, 108, 15, 134)])
                .fill(LinearGradient(stops: [
                    .init(color: Color(red: 68/255, green: 134/255, blue: 245/255), location: 0),
                    .init(color: Color(red: 78/255, green: 140/255, blue: 242/255), location: 0.44),
                    .init(color: Color(red: 162/255, green: 192/255, blue: 235/255), location: 1),
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .aspectRatio(240 / 180, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// One ribbon from the kit's 240×180 symbol artboard, scaled to the frame.
private struct WaveShape: Shape {
    let start: (CGFloat, CGFloat)
    let curves: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)]

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 240, sy = rect.height / 180
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(start.0, start.1))
        for c in curves { path.addCurve(to: p(c.4, c.5), control1: p(c.0, c.1), control2: p(c.2, c.3)) }
        path.closeSubpath()
        return path
    }
}
