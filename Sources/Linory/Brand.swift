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
/// With `drift` > 0 it comes alive: a slow wave travels along both ribbons and a soft light glides across.
struct LinorySymbol: View, Animatable {
    /// Animation clock in seconds; only matters while `drift` > 0.
    var time: Double = 0
    /// 0 = at rest (the static logo), 1 = fully animated. Animatable so the ribbons can settle smoothly.
    var drift: Double = 0
    var animatableData: Double { get { drift } set { drift = newValue } }

    private static let upperGradient = LinearGradient(stops: [
        .init(color: Color(red: 175/255, green: 201/255, blue: 241/255), location: 0),
        .init(color: Color(red: 128/255, green: 168/255, blue: 233/255), location: 0.47),
        .init(color: Color(red: 82/255, green: 124/255, blue: 205/255), location: 1),
    ], startPoint: UnitPoint(x: 0, y: 0.2), endPoint: UnitPoint(x: 1, y: 0.9))
    private static let lowerGradient = LinearGradient(stops: [
        .init(color: Color(red: 68/255, green: 134/255, blue: 245/255), location: 0),
        .init(color: Color(red: 78/255, green: 140/255, blue: 242/255), location: 0.44),
        .init(color: Color(red: 162/255, green: 192/255, blue: 235/255), location: 1),
    ], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Wave phase: one swell travels along the ribbons every 4.8 s; the lower ribbon trails slightly.
    private var phase: Double { time * 2 * .pi / 4.8 }

    var body: some View {
        ZStack {
            WaveShape.upper(ripple: 5.5 * drift, phase: phase).fill(Self.upperGradient)
            WaveShape.lower(ripple: 5.5 * drift, phase: phase - 0.8).fill(Self.lowerGradient)
        }
        .overlay { if drift > 0 { sheen } }
        .aspectRatio(240 / 180, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// A soft band of light crossing the ribbons once every 6 s, clipped to their shape.
    private var sheen: some View {
        GeometryReader { geo in
            let cycle = time.truncatingRemainder(dividingBy: 6) / 1.8 // sweep takes 1.8 s, then rests
            let band = geo.size.width * 0.6
            LinearGradient(colors: [.white.opacity(0), .white.opacity(0.3), .white.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: band)
                .rotationEffect(.degrees(18))
                .offset(x: -band + (geo.size.width + band) * Motion.easeInOut(min(1, cycle)))
                .opacity(cycle < 1 ? drift : 0)
                .blendMode(.plusLighter)
        }
        .mask {
            ZStack {
                WaveShape.upper(ripple: 5.5 * drift, phase: phase)
                WaveShape.lower(ripple: 5.5 * drift, phase: phase - 0.8)
            }
        }
        .allowsHitTesting(false)
    }
}

/// One ribbon from the kit's 240×180 symbol artboard, scaled to the frame. `ripple` bends it along a
/// travelling sine wave (in artboard units); top and bottom edges move together, so its thickness holds.
private struct WaveShape: Shape {
    let start: (CGFloat, CGFloat)
    let curves: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)]
    var ripple: Double = 0
    var phase: Double = 0

    static func upper(ripple: Double, phase: Double) -> WaveShape {
        WaveShape(start: (57, 78), curves: [(80, 48, 100, 45, 121, 49), (160, 61, 175, 95, 224, 50), (215, 87, 186, 108, 160, 94), (125, 77, 102, 52, 57, 78)], ripple: ripple, phase: phase)
    }
    static func lower(ripple: Double, phase: Double) -> WaveShape {
        WaveShape(start: (15, 134), curves: [(39, 92, 67, 91, 95, 101), (132, 115, 156, 140, 204, 112), (193, 147, 168, 163, 132, 148), (93, 130, 59, 108, 15, 134)], ripple: ripple, phase: phase)
    }

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 240, sy = rect.height / 180
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let bend = ripple * sin(Double(x) / 240 * 2 * .pi - phase)
            return CGPoint(x: rect.minX + x * sx, y: rect.minY + (y + bend) * sy)
        }
        var path = Path()
        path.move(to: p(start.0, start.1))
        for c in curves { path.addCurve(to: p(c.4, c.5), control1: p(c.0, c.1), control2: p(c.2, c.3)) }
        path.closeSubpath()
        return path
    }
}

/// Frosted glass behind the overlay and Settings: real behind-window blur plus the brand's ink-blue tint.
struct GlassBackground: View {
    var cornerRadius: CGFloat
    /// 0 = no glass at all (floating text), 1 = full glass.
    var strength: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            VisualEffectBlur().opacity(strength)
            shape.fill(LinearGradient(colors: [Color(red: 0.16, green: 0.19, blue: 0.27), Brand.ink],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(0.72 * strength)
            // Light catching the top edge, as in the brand concept.
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .opacity(strength)
        }
        .clipShape(shape)
    }
}

private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The highlight behind the current lyric line: a soft glass pill.
struct LyricHighlight: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        shape.fill(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

/// Native panel background: Liquid Glass on macOS 26+, the standard popover material before that.
/// Follows the system Light/Dark appearance.
struct SystemPanelBackground: View {
    var cornerRadius: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            SystemMaterial().clipShape(shape)
        }
        #else
        SystemMaterial().clipShape(shape)
        #endif
    }
}

private struct SystemMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Motion tokens. Strong ease-out for things appearing; an interruptible spring for lines that move.
enum Motion {
    static func easeOut(_ duration: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
    /// New song: rare, so it may take a little longer and feel special.
    static let reveal = easeOut(0.55)
    /// Line changes happen every few seconds: a spring keeps velocity when lines come quickly.
    static let lineChange = Animation.spring(response: 0.48, dampingFraction: 0.88)
    static let press = easeOut(0.14)
    /// Smoothstep easing for values driven by a clock rather than by a SwiftUI animation.
    static func easeInOut(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}

/// Fades, lifts and un-blurs content in when it appears. Give the container a new `.id` to replay it
/// (e.g. per song), so each song gets its own entrance.
struct Reveal: ViewModifier {
    var delay: Double = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let moving = !shown && !reduceMotion
        content
            .opacity(shown ? 1 : 0)
            .offset(y: moving ? 8 : 0)
            .blur(radius: moving ? 6 : 0)
            .onAppear { withAnimation(Motion.reveal.delay(delay)) { shown = true } }
    }
}

/// The old song drifts up and blurs away while the new one comes in.
private struct ExitEffect: ViewModifier {
    let progress: Double
    func body(content: Content) -> some View {
        content.opacity(1 - progress).offset(y: -10 * progress).blur(radius: 6 * progress)
    }
}

extension AnyTransition {
    /// Insertion is handled by `Reveal` (staggered); removal drifts up and blurs out.
    static var songSwap: AnyTransition {
        .asymmetric(insertion: .identity, removal: .modifier(active: ExitEffect(progress: 1), identity: ExitEffect(progress: 0)))
    }
}

/// Lets the borderless overlay be dragged from any spot that is not a control.
/// (`isMovableByWindowBackground` does not reach through SwiftUI content.)
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override var mouseDownCanMoveWindow: Bool { true }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
}

/// Subtle scale-down while pressed, so every click feels heard.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// Three dots that fill one after another while waiting for singing (intro, instrumental break),
/// breathing gently so the wait feels alive.
struct BreakDots: View {
    let progress: Double
    let time: TimeInterval
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let breathe = reduceMotion ? 1 : 1 + 0.06 * sin(time * 2 * .pi / 1.8)
        HStack(spacing: size * 0.3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.primary)
                    .frame(width: size * 0.32, height: size * 0.32)
                    .opacity(0.22 + 0.78 * min(1, max(0, progress * 3 - Double(i))))
            }
        }
        .scaleEffect(breathe, anchor: .leading)
        .frame(height: size * 1.2, alignment: .leading)
        .accessibilityLabel("♪")
    }
}
