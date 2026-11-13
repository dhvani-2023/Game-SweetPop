import SwiftUI
import GameKit

/// Confetti + sparkles over a dialog (the Win dialog's front layer, reusable): an `Effects` pool on its own frame
/// loop, which only runs while something is on screen.
@MainActor
final class DialogFx {
    let loop = GameLoop()
    let fx = Effects()
    /// Size and global origin of the full-screen front canvas.
    var size: CGSize = .zero
    var origin: CGPoint = .zero

    init() {
        loop.maxDelta = 0.05
        loop.onTick = { [weak self] dt in self?.step(Float(dt)) }
    }

    private func step(_ dt: Float) {
        fx.update(dt)
        if !fx.isBusy { loop.stop() }
    }

    func confetti() {
        guard size.width > 0 else { return }
        fx.confetti(Float(size.width), Float(size.height))
        loop.start()
    }

    /// Sparkles at a point given in global coordinates.
    func sparkles(atGlobal c: CGPoint, _ n: Int = 12, color: Color = Color(argb: 0xFFFFF4B0)) {
        fx.sparkles(Float(c.x - origin.x), Float(c.y - origin.y), n, 46, 15, color)
        loop.start()
    }

    func stop() {
        loop.stop()
        fx.clear()
    }
}

/// Full-screen canvas for a [DialogFx] (put it in `SweetDialog`'s `front:`).
struct DialogFxCanvas: View {
    let model: DialogFx

    var body: some View {
        let frameTick = model.loop.frame
        let model = self.model
        Canvas { ctx, _ in
            _ = frameTick // capture the changing frame so SwiftUI redraws this Canvas every tick
            model.fx.draw(ctx)
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { r in
            model.size = r.size
            model.origin = r.origin
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Slowly turning golden rays (behind prizes), still with Reduce Motion.
struct PrizeRays: View {
    var color: Color = Color(argb: 0xFFFFD34D)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let rays: Path = {
        var p = Path()
        for i in 0..<14 {
            let a = Double(i) * 2 * Double.pi / 14
            let w = 0.1
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: Foundation.cos(a - w), y: Foundation.sin(a - w)))
            p.addLine(to: CGPoint(x: Foundation.cos(a + w), y: Foundation.sin(a + w)))
            p.closeSubpath()
        }
        return p
    }()

    var body: some View {
        let ray = Gradient(colors: [color.opacity(0.6), color.opacity(0)])
        let glow = Gradient(colors: [Color(argb: 0xFFFFF4B0).opacity(0.75), .clear])
        ClockView(paused: reduceMotion || Motion.reduce) { t in
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2
                guard r > 0 else { return }
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.8, y: c.y - r * 0.8, width: r * 1.6, height: r * 1.6)),
                         with: .radialGradient(glow, center: c, startRadius: 0, endRadius: r * 0.8))
                var g = ctx
                g.translateBy(x: c.x, y: c.y)
                g.rotate(by: .degrees(Double(t * 16)))
                g.scaleBy(x: r, y: r)
                g.fill(Self.rays, with: .radialGradient(ray, center: .zero, startRadius: 0, endRadius: 1))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
