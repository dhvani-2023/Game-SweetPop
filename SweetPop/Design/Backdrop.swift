import SwiftUI
import GameKit

/// Kotlin `rememberClock()`: seconds since this view appeared, updated every display frame (120 Hz on ProMotion).
/// Use as `ClockView { t in … }` and read `t` in drawing code.
struct ClockView<Content: View>: View {
    var paused: Bool = false
    let content: (Float) -> Content

    @State private var start = Date()

    init(paused: Bool = false, @ViewBuilder content: @escaping (Float) -> Content) {
        self.paused = paused
        self.content = content
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: paused)) { tl in
            content(Float(max(0, tl.date.timeIntervalSince(start))))
        }
    }
}

private struct Bubble {
    let x: Float, speed: Float, r: Float, sway: Float, phase: Float, swaySpeed: Float
}

private struct Floater {
    let x: Float, speed: Float, size: Float, phase: Float, color: CandyColor, spin: Float
}

/// Sunset gradient + rotating sunburst + vignette + rising bubbles and faded candies (spec 4.3).
/// Fills the space it is given; put it behind the screens with `.ignoresSafeArea()`.
/// Ambient motion stops (static frame) with Reduce Motion.
struct Backdrop: View {
    var raysCenterY: Float = 0.66
    var subtle: Bool = false
    var decorations: Bool = true

    @Environment(\.palette) private var p
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Kotlin `remember { List(if (subtle) 10 else 15) … }` — fixed at first appearance, like the remember block.
    @State private var bubbleCount: Int
    @State private var floaterCount: Int
    @State private var start = Date()

    init(raysCenterY: Float = 0.66, subtle: Bool = false, decorations: Bool = true) {
        self.raysCenterY = raysCenterY
        self.subtle = subtle
        self.decorations = decorations
        _bubbleCount = State(initialValue: subtle ? 10 : 15)
        _floaterCount = State(initialValue: subtle ? 3 : 5)
    }

    // Random(42) / Random(7): the shorter lists are prefixes of the longer ones (same draw order).
    private static let allBubbles: [Bubble] = {
        let r = JavaRandom(42)
        return (0..<15).map { _ in
            Bubble(x: r.nextFloat(), speed: 0.025 + r.nextFloat() * 0.035, r: 6 + r.nextFloat() * 16,
                   sway: 8 + r.nextFloat() * 18, phase: r.nextFloat(), swaySpeed: 0.5 + r.nextFloat())
        }
    }()

    private static let allFloaters: [Floater] = {
        let r = JavaRandom(7)
        return (0..<5).map { _ in
            Floater(x: r.nextFloat(), speed: 0.012 + r.nextFloat() * 0.012, size: 40 + r.nextFloat() * 22, phase: r.nextFloat(),
                    color: CandyColor.PLAYABLE[r.nextInt(6)], spin: r.nextFloat() * 2 - 1)
        }
    }()

    /// 24 sunburst wedges around the origin, radius 1300 dp (points).
    private static let rays: Path = {
        var path = Path()
        let radius: Float = 1300
        let n = 24
        let half = Float(Double.pi / Double(n) / 2)
        for i in 0..<n {
            let a = Float(Double(i) * 2 * Double.pi / Double(n))
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: CGFloat(radius * Kt.cos(a - half)), y: CGFloat(radius * Kt.sin(a - half))))
            path.addLine(to: CGPoint(x: CGFloat(radius * Kt.cos(a + half)), y: CGFloat(radius * Kt.sin(a + half))))
            path.closeSubpath()
        }
        return path
    }()

    var body: some View {
        let paused = reduceMotion || GameKit.Motion.reduce
        TimelineView(.animation(minimumInterval: nil, paused: paused)) { tl in
            let t = paused ? 0 : Float(max(0, tl.date.timeIntervalSince(start)))
            Canvas(opaque: true) { ctx, size in
                draw(ctx, size, t)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ t: Float) {
        let w = size.width
        let h = size.height
        let full = CGRect(origin: .zero, size: size)
        ctx.fill(Path(full), with: .linearGradient(Gradient(colors: [p.bgTop, p.bgBottom]),
                                                    startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        let rayBase = RGBA(p.rays)
        let rayColor = subtle ? rayBase.with(alpha: rayBase.a * 0.6).quantized : rayBase
        let rayGradient = Gradient(colors: [rayColor.color, rayColor.with(alpha: rayColor.a * 0.55).quantized.color, RGBA.transparent.color])
        var rc = ctx
        rc.translateBy(x: w / 2, y: h * CGFloat(raysCenterY))
        rc.rotate(by: .degrees(Double(t * 4)))
        rc.fill(Self.rays, with: .radialGradient(rayGradient, center: .zero, startRadius: 0,
                                                 endRadius: CGFloat(Kt.hypot(Float(w), Float(h)) * 0.9)))

        if decorations {
            drawBubbles(ctx, size, t)
            drawFloaters(ctx, size, t)
        }

        let vignette = Gradient(stops: [
            .init(color: RGBA.transparent.color, location: 0),
            .init(color: RGBA.transparent.color, location: 0.55),
            .init(color: srgbColor(RGBA(0, 0, 0, 0.55)), location: 1),
        ])
        ctx.fill(Path(full), with: .radialGradient(vignette, center: CGPoint(x: w / 2, y: h / 2), startRadius: 0,
                                                   endRadius: CGFloat(Kt.hypot(Float(w), Float(h)) / 2)))
    }

    private func drawBubbles(_ ctx: GraphicsContext, _ size: CGSize, _ t: Float) {
        let h = Float(size.height)
        let density: Float = 1
        for b in Self.allBubbles.prefix(bubbleCount) {
            let r = b.r * density
            let span = h + r * 4
            let prog = fmodf(b.phase + t * b.speed, 1)
            let y = h + r * 2 - prog * span
            let x = b.x * Float(size.width) + Kt.sin(t * b.swaySpeed + b.phase * 6) * b.sway * density
            let rr = CGFloat(r)
            let circle = Path(ellipseIn: CGRect(x: CGFloat(x) - rr, y: CGFloat(y) - rr, width: rr * 2, height: rr * 2))
            ctx.fill(circle, with: RGBA.white.shading(alpha: 0.10))
            ctx.stroke(circle, with: RGBA.white.shading(alpha: 0.28), lineWidth: CGFloat(1.4 * density))
            let hr = rr * 0.22
            let hx = CGFloat(x) - rr * 0.38, hy = CGFloat(y) - rr * 0.38
            ctx.fill(Path(ellipseIn: CGRect(x: hx - hr, y: hy - hr, width: hr * 2, height: hr * 2)), with: RGBA.white.shading(alpha: 0.45))
        }
    }

    private func drawFloaters(_ ctx: GraphicsContext, _ size: CGSize, _ t: Float) {
        let h = Float(size.height)
        let density: Float = 1
        let decor = decorBitmapPx(displayScale)
        for f in Self.allFloaters.prefix(floaterCount) {
            let s = f.size * density
            let span = h + s * 3
            let prog = fmodf(f.phase + t * f.speed, 1)
            let y = h + s - prog * span
            let x = f.x * Float(size.width) + Kt.sin(t * 0.6 + f.phase * 5) * 22 * density
            ctx.drawCandy(
                f.color, .NONE, CGFloat(x), CGFloat(y), CGFloat(s),
                alpha: 0.16,
                rotationDeg: CGFloat(Kt.sin(t * 0.4 + f.phase * 3) * 25 * f.spin),
                bitmapPx: decor
            )
        }
    }
}
