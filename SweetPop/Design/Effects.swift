import SwiftUI
import GameKit

/// Easing curves shared by the board and effects. All take and return 0..1.
enum Easing {
    static func inOut(_ t: Float) -> Float { t < 0.5 ? 2 * t * t : 1 - Kt.pow(-2 * t + 2, 2) / 2 }
    static func inQuad(_ t: Float) -> Float { t * t }
    static func outCubic(_ t: Float) -> Float { 1 - Kt.pow(1 - t, 3) }

    static func outBack(_ t: Float, _ s: Float = 1.70158) -> Float {
        let u = t - 1
        return 1 + (s + 1) * u * u * u + s * u * u
    }

    static func outElastic(_ t: Float) -> Float {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        let c4 = Float(2 * Double.pi / 3)
        return Kt.pow(2, -10 * t) * Kt.sin((t * 10 - 0.75) * c4) + 1
    }

    static func outBounce(_ t: Float) -> Float {
        let n1: Float = 7.5625
        let d1: Float = 2.75
        var x = t
        if x < 1 / d1 { return n1 * x * x }
        if x < 2 / d1 { x -= 1.5 / d1; return n1 * x * x + 0.75 }
        if x < 2.5 / d1 { x -= 2.25 / d1; return n1 * x * x + 0.9375 }
        x -= 2.625 / d1
        return n1 * x * x + 0.984375
    }
}

/// Glow colour used for particles and floating scores of a candy colour.
func glowColor(_ c: CandyColor) -> Color {
    c == .NONE ? Color(argb: 0xFFFFD27A) : lighten(Color(argb: c.argb), 0.25)
}

/**
 * Lightweight pooled particle layer: candy bursts, sparkles, beams, zaps, shockwaves, confetti,
 * floating scores, praise words, collect fly-ins and screen shake. Coordinates are in units of the
 * canvas it is drawn into. Call [update] every frame and [draw] from one Canvas.
 *
 * iOS: SwiftUI canvases work in points, so [density] (canvas units per dp) stays 1 — do NOT set it to the
 * display scale. Speeds tuned in Android pixels scale by `k = density / 2.75` exactly as on Android.
 * Per-frame work allocates nothing: particles are value types in a pre-reserved array compacted in place,
 * texts are laid out once (cached glyph paths) when they are emitted.
 */
final class Effects {
    var density: Float = 1
    private var k: Float { density / 2.75 }
    private(set) var time: Float = 0
    private let rnd = JavaRandom(Int64(bitPattern: UInt64(DispatchTime.now().uptimeNanoseconds) ^ 0x5DEECE66D))
    private let zapRnd = JavaRandom(0)

    private struct Particle {
        var kind = 0
        var x: Float = 0
        var y: Float = 0
        var vx: Float = 0
        var vy: Float = 0
        var age: Float = 0
        var life: Float = 1
        var size: Float = 1
        var color = RGBA.white
        var rot: Float = 0
        var vr: Float = 0
        var gravity: Float = 0
        var drag: Float = 0
    }

    private struct FloatText {
        let text: TextPath
        let x: Float
        let y: Float
        let color: RGBA
        let sizeSp: Float
        let start: Float
        let kind: Int
        let life: Float
    }

    private struct Beam {
        let x0: Float, y0: Float, x1: Float, y1: Float, ox: Float, oy: Float, thick: Float
        let color: RGBA
        let start: Float
    }

    private struct Zap {
        let x0: Float, y0: Float, x1: Float, y1: Float
        let start: Float
        let seed: Int
    }

    private struct Shock {
        let x: Float, y: Float, r: Float
        let start: Float
        let color: RGBA
    }

    private struct Flyer {
        let color: CandyColor
        let special: SpecialType
        let x0: Float, y0: Float, x1: Float, y1: Float
        let cell: Float
        let start: Float
        let dur: Float
        let onArrive: () -> Void
    }

    private var particles: [Particle] = []
    private var texts: [FloatText] = []
    private var beams: [Beam] = []
    private var zaps: [Zap] = []
    private var shocks: [Shock] = []
    private var flyers: [Flyer] = []
    private var arrivals: [() -> Void] = []
    private var shakeStart: Float = -10
    private var shakeStrength: Float = 0

    private static let DOT = 0
    private static let SPARKLE = 1
    private static let GLOW = 2
    private static let CONFETTI_SQ = 3
    private static let CONFETTI_CIRCLE = 4
    private static let CRUMB = 5

    private static let T_SCORE = 0
    private static let T_PRAISE = 1
    private static let T_BANNER = 2
    private static let MAX_PARTICLES = 700

    private static let PlumOutline = RGBA(argb: 0xFF4A1C6E)
    private static let PraiseGradient = Gradient(colors: [Color(argb: 0xFFFFF27A), Color(argb: 0xFFFF9A3D), Color(argb: 0xFFFF4FA3)])
    private static let ZapGlow = RGBA(argb: 0xFFB98CFF)

    init() {
        particles.reserveCapacity(Self.MAX_PARTICLES)
        texts.reserveCapacity(16)
        beams.reserveCapacity(32)
        zaps.reserveCapacity(64)
        shocks.reserveCapacity(16)
        flyers.reserveCapacity(32)
        arrivals.reserveCapacity(32)
    }

    func clear() {
        particles.removeAll(keepingCapacity: true)
        texts.removeAll(keepingCapacity: true)
        beams.removeAll(keepingCapacity: true)
        zaps.removeAll(keepingCapacity: true)
        shocks.removeAll(keepingCapacity: true)
        flyers.removeAll(keepingCapacity: true)
        shakeStrength = 0
    }

    var isBusy: Bool { !particles.isEmpty || !texts.isEmpty || !flyers.isEmpty }

    private var canSpawn: Bool { particles.count < Self.MAX_PARTICLES }

    @inline(__always)
    private func rf(_ a: Float, _ b: Float) -> Float { a + rnd.nextFloat() * (b - a) }

    // ---------------------------------------------------------------- emitters

    /// 7 coloured dots + 2 sparkles + a soft glow flash.
    func burst(_ x: Float, _ y: Float, _ color: Color, _ cell: Float) {
        let c = RGBA(color)
        for _ in 0..<7 {
            guard canSpawn else { return }
            var p = Particle()
            let a = rf(0, Float(2 * Double.pi))
            let s = rf(300, 750) * k
            p.kind = Self.DOT
            p.x = x; p.y = y
            p.vx = Kt.cos(a) * s; p.vy = Kt.sin(a) * s - 120 * k
            p.life = rf(0.5, 0.8)
            p.size = cell * rf(0.05, 0.1)
            p.color = c
            p.gravity = 1100 * k
            p.drag = 2.6
            particles.append(p)
        }
        for _ in 0..<2 { spawnSparkle(x + rf(-0.3, 0.3) * cell, y + rf(-0.3, 0.3) * cell, cell * rf(0.18, 0.28)) }
        guard canSpawn else { return }
        var g = Particle()
        g.kind = Self.GLOW
        g.x = x; g.y = y; g.vx = 0; g.vy = 0
        g.life = 0.24
        g.size = cell * 0.8
        g.color = c
        particles.append(g)
    }

    /// A 4-point star glint.
    func sparkle(_ x: Float, _ y: Float, _ size: Float, _ color: Color = .white, life: Float = 0.55) {
        spawnSparkle(x, y, size, RGBA(color), life)
    }

    private func spawnSparkle(_ x: Float, _ y: Float, _ size: Float, _ color: RGBA = .white, _ life: Float = 0.55) {
        guard canSpawn else { return }
        var p = Particle()
        p.kind = Self.SPARKLE
        p.x = x; p.y = y
        p.vx = rf(-20, 20) * k; p.vy = rf(-40, -10) * k
        p.life = life * rf(0.8, 1.2)
        p.size = size
        p.color = color
        p.vr = rf(-90, 90)
        particles.append(p)
    }

    func sparkles(_ x: Float, _ y: Float, _ n: Int, _ spread: Float, _ size: Float, _ color: Color = .white) {
        spawnSparkles(x, y, n, spread, size, RGBA(color))
    }

    private func spawnSparkles(_ x: Float, _ y: Float, _ n: Int, _ spread: Float, _ size: Float, _ color: RGBA) {
        for _ in 0..<max(0, n) { spawnSparkle(x + rf(-1, 1) * spread, y + rf(-1, 1) * spread, size * rf(0.7, 1.2), color) }
    }

    /// Cream crumbs for frosting hits.
    func crumbs(_ x: Float, _ y: Float, _ cell: Float, pink: Bool) {
        let base = pink ? RGBA(argb: 0xFFFFD3E6) : RGBA(argb: 0xFFFFF1D6)
        for i in 0..<8 {
            guard canSpawn else { return }
            var p = Particle()
            let a = rf(Float(Double.pi * 1.1), Float(Double.pi * 1.9))
            let s = rf(180, 420) * k
            p.kind = Self.CRUMB
            p.x = x + rf(-0.3, 0.3) * cell; p.y = y + rf(-0.3, 0.3) * cell
            p.vx = Kt.cos(a) * s; p.vy = Kt.sin(a) * s
            p.life = rf(0.5, 0.8)
            p.size = cell * rf(0.07, 0.13)
            p.color = i % 3 == 0 ? RGBA(argb: 0xFFE6C996) : base
            p.gravity = 1400 * k
            p.drag = 1.5
            p.vr = rf(-400, 400)
            particles.append(p)
        }
    }

    /// Glowing pill that grows from (ox, oy) to the full span (x0,y0)–(x1,y1).
    func beam(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ ox: Float, _ oy: Float, _ cell: Float, _ color: Color) {
        beams.append(Beam(x0: x0, y0: y0, x1: x1, y1: y1, ox: ox, oy: oy, thick: cell * 0.46, color: RGBA(color), start: time))
        let n = 8
        for i in 0...n {
            let t = Float(i) / Float(n)
            spawnSparkle(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, cell * 0.25, .white, 0.5)
        }
    }

    func zap(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) {
        zaps.append(Zap(x0: x0, y0: y0, x1: x1, y1: y1, start: time, seed: rnd.nextInt()))
    }

    func shockwave(_ x: Float, _ y: Float, _ radius: Float, _ color: Color = .white) {
        shocks.append(Shock(x: x, y: y, r: radius, start: time, color: RGBA(color)))
    }

    func shake(_ strengthPx: Float) {
        let cur = currentShake()
        if strengthPx >= cur {
            shakeStrength = strengthPx
            shakeStart = time
        }
    }

    private func currentShake() -> Float {
        let t = (time - shakeStart) / 0.35
        return t >= 0 && t <= 1 ? shakeStrength * (1 - t) : 0
    }

    /// Board offset for the decaying screen shake.
    func shakeOffset() -> CGPoint {
        let s = currentShake()
        if s <= 0 { return .zero }
        return CGPoint(x: CGFloat(Kt.sin(time * 71) * s), y: CGFloat(Kt.cos(time * 53) * s * 0.7))
    }

    /// 90 squares and circles in random hues falling with spin.
    func confetti(_ width: Float, _ height: Float) {
        for i in 0..<90 {
            guard canSpawn else { return }
            var p = Particle()
            p.kind = i % 3 == 0 ? Self.CONFETTI_CIRCLE : Self.CONFETTI_SQ
            p.x = rf(0, width)
            p.y = rf(-height * 0.25, -10)
            p.vx = rf(-70, 70) * k
            p.vy = rf(140, 300) * k
            p.life = rf(2.2, 3.4)
            p.size = rf(7, 12) * density
            p.color = hsvRGBA(rf(0, 360), 0.7, 1)
            p.gravity = 90 * k
            p.drag = 0.4
            p.rot = rf(0, 360)
            p.vr = rf(-360, 360)
            particles.append(p)
        }
    }

    func floatScore(_ points: Int, _ x: Float, _ y: Float, _ color: Color) {
        texts.append(makeText(String(points), x, y, RGBA(color), 22, Self.T_SCORE, 0.9))
    }

    /// Big elastic praise word in the middle of the canvas with sparkles.
    func praise(_ word: String, _ x: Float, _ y: Float, _ sizeSp: Float = 50) {
        texts.append(makeText(word, x, y, .white, sizeSp, Self.T_PRAISE, 1.3))
        spawnSparkles(x, y, 10, 120 * k, 16 * density, RGBA(argb: 0xFFFFF4B0))
    }

    /// Smaller message (Shuffle!, 5 moves left!, Locked!).
    func banner(_ text: String, _ x: Float, _ y: Float, _ sizeSp: Float = 36, _ color: Color = .white) {
        texts.append(makeText(text, x, y, RGBA(color), sizeSp, Self.T_BANNER, 1.4))
    }

    /// Flies a small candy copy along a curve (0.6 s), then calls [onArrive].
    func flyCandy(
        _ color: CandyColor, _ special: SpecialType, _ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ cell: Float,
        _ onArrive: @escaping () -> Void
    ) {
        flyers.append(Flyer(color: color, special: special, x0: x0, y0: y0, x1: x1, y1: y1, cell: cell, start: time, dur: 0.6, onArrive: onArrive))
    }

    private func makeText(_ text: String, _ x: Float, _ y: Float, _ color: RGBA, _ sizeSp: Float, _ kind: Int, _ life: Float) -> FloatText {
        let tp = TextPaths.layout(text, fontSize: CGFloat(sizeSp * density))
        return FloatText(text: tp, x: x, y: y, color: color, sizeSp: sizeSp, start: time, kind: kind, life: life)
    }

    // ---------------------------------------------------------------- update

    func update(_ dt: Float) {
        time += dt
        var w = 0
        let n = particles.count
        let t3 = time * 3
        for i in 0..<n {
            var p = particles[i]
            p.age += dt
            if p.age >= p.life { continue }
            let dragK = 1 / (1 + p.drag * dt)
            p.vx *= dragK
            p.vy = p.vy * dragK + p.gravity * dt
            if p.kind == Self.CONFETTI_SQ || p.kind == Self.CONFETTI_CIRCLE { p.x += Kt.sin(t3 + p.rot * 0.05) * 30 * k * dt }
            p.x += p.vx * dt
            p.y += p.vy * dt
            p.rot += p.vr * dt
            particles[w] = p
            w += 1
        }
        if w < n { particles.removeLast(n - w) }
        let now = time
        texts.removeAll { now - $0.start > $0.life }
        beams.removeAll { now - $0.start > 0.55 }
        zaps.removeAll { now - $0.start > 0.4 }
        shocks.removeAll { now - $0.start > 0.45 }
        if !flyers.isEmpty {
            var fw = 0
            let fn = flyers.count
            for i in 0..<fn {
                let f = flyers[i]
                if now - f.start >= f.dur { arrivals.append(f.onArrive) } else { flyers[fw] = f; fw += 1 }
            }
            if fw < fn { flyers.removeLast(fn - fw) }
            if !arrivals.isEmpty {
                for a in arrivals { a() }
                arrivals.removeAll(keepingCapacity: true)
            }
        }
    }

    // ---------------------------------------------------------------- draw

    /// Unit 4-point star centred on 0,0 with radius 1.
    private static let starPath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -1))
        p.addQuadCurve(to: CGPoint(x: 1, y: 0), control: CGPoint(x: 0.12, y: -0.12))
        p.addQuadCurve(to: CGPoint(x: 0, y: 1), control: CGPoint(x: 0.12, y: 0.12))
        p.addQuadCurve(to: CGPoint(x: -1, y: 0), control: CGPoint(x: -0.12, y: 0.12))
        p.addQuadCurve(to: CGPoint(x: 0, y: -1), control: CGPoint(x: -0.12, y: -0.12))
        p.closeSubpath()
        return p
    }()

    func draw(_ ctx: GraphicsContext) {
        for s in shocks {
            let t = ((time - s.start) / 0.45).coerceIn(0, 1)
            let r = CGFloat(s.r * Easing.outCubic(t))
            let c = CGPoint(x: CGFloat(s.x), y: CGFloat(s.y))
            let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            // Android adds a raw 2 px to the ring width: 2 px at the reference density = 2·k.
            ctx.stroke(circle, with: s.color.shading(alpha: 0.7 * (1 - t)), lineWidth: CGFloat((18 * k) * (1 - t) + 2 * k))
            let r2 = r * 0.9
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r2, y: c.y - r2, width: r2 * 2, height: r2 * 2)), with: s.color.shading(alpha: 0.18 * (1 - t)))
        }
        for b in beams { drawBeam(ctx, b) }
        for z in zaps { drawZap(ctx, z) }
        for p in particles { drawParticle(ctx, p) }
        for f in flyers {
            let t = ((time - f.start) / f.dur).coerceIn(0, 1)
            let e = Easing.inOut(t)
            let mx = (f.x0 + f.x1) / 2 - (f.y1 - f.y0) * 0.25
            let my = (f.y0 + f.y1) / 2 - Kt.hypot(f.x1 - f.x0, f.y1 - f.y0) * 0.35
            let u = 1 - e
            let x = u * u * f.x0 + 2 * u * e * mx + e * e * f.x1
            let y = u * u * f.y0 + 2 * u * e * my + e * e * f.y1
            ctx.drawCandy(f.color, f.special, CGFloat(x), CGFloat(y), CGFloat(f.cell),
                          scaleX: CGFloat(1 - 0.45 * e), scaleY: CGFloat(1 - 0.45 * e))
        }
        for t in texts { drawFloatText(ctx, t) }
    }

    @inline(__always)
    private func circlePath(_ x: Float, _ y: Float, _ r: Float) -> Path {
        let rr = CGFloat(max(0, r))
        return Path(ellipseIn: CGRect(x: CGFloat(x) - rr, y: CGFloat(y) - rr, width: rr * 2, height: rr * 2))
    }

    private func drawParticle(_ ctx: GraphicsContext, _ p: Particle) {
        let t = p.age / p.life
        switch p.kind {
        case Self.DOT:
            let a = t > 0.6 ? 1 - (t - 0.6) / 0.4 : 1
            ctx.fill(circlePath(p.x, p.y, p.size * (1 - t * 0.6)), with: p.color.shading(alpha: a))
            ctx.fill(circlePath(p.x - p.size * 0.25, p.y - p.size * 0.25, p.size * 0.4 * (1 - t * 0.6)), with: RGBA.white.shading(alpha: a * 0.5))
        case Self.SPARKLE:
            let a = t < 0.25 ? t / 0.25 : 1 - (t - 0.25) / 0.75
            let s = p.size * (0.6 + 0.6 * Kt.sin(t * Float(Double.pi)))
            var c = ctx
            c.translateBy(x: CGFloat(p.x), y: CGFloat(p.y))
            c.rotate(by: .degrees(Double(p.rot)))
            c.scaleBy(x: CGFloat(s), y: CGFloat(s))
            c.fill(Self.starPath, with: p.color.shading(alpha: a.coerceIn(0, 1)))
        case Self.GLOW:
            // [white α a, colour α 0.6a, transparent] = opacity a × a cached [white, colour 0.6, transparent].
            let a = (1 - t) * 0.6
            let center = CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
            var c = ctx
            c.opacity *= Double(a.coerceIn(0, 1))
            c.fill(circlePath(p.x, p.y, p.size), with: .radialGradient(glowGradient(p.color), center: center, startRadius: 0, endRadius: CGFloat(p.size)))
        case Self.CONFETTI_SQ:
            let a = t > 0.85 ? (1 - t) / 0.15 : 1
            var c = ctx
            c.translateBy(x: CGFloat(p.x), y: CGFloat(p.y))
            c.rotate(by: .degrees(Double(p.rot)))
            let h = p.size * 0.6 * (0.4 + 0.6 * abs(Kt.sin(p.rot * 0.03)))
            c.fill(Path(CGRect(x: CGFloat(-p.size / 2), y: CGFloat(-p.size * 0.3), width: CGFloat(p.size), height: CGFloat(h))),
                   with: p.color.shading(alpha: a))
        case Self.CONFETTI_CIRCLE:
            let a = t > 0.85 ? (1 - t) / 0.15 : 1
            ctx.fill(circlePath(p.x, p.y, p.size * 0.4), with: p.color.shading(alpha: a))
        case Self.CRUMB:
            let a = t > 0.6 ? 1 - (t - 0.6) / 0.4 : 1
            var c = ctx
            c.translateBy(x: CGFloat(p.x), y: CGFloat(p.y))
            c.rotate(by: .degrees(Double(p.rot)))
            let sz = CGFloat(p.size)
            c.fill(Path(roundedRect: CGRect(x: -sz / 2, y: -sz / 2, width: sz, height: sz), cornerRadius: sz * 0.25, style: .circular),
                   with: p.color.shading(alpha: a))
        default:
            break
        }
    }

    private var glowGradients: [RGBA: Gradient] = [:]

    private func glowGradient(_ c: RGBA) -> Gradient {
        if let g = glowGradients[c] { return g }
        let g = Gradient(stops: [
            .init(color: RGBA.white.color, location: 0),
            .init(color: c.with(alpha: 0.6).color, location: 0.5),
            .init(color: RGBA.transparent.color, location: 1),
        ])
        glowGradients[c] = g
        return g
    }

    private func drawBeam(_ ctx: GraphicsContext, _ b: Beam) {
        let t = time - b.start
        let grow = Easing.outCubic((t / 0.35).coerceIn(0, 1))
        let fade: Float = t > 0.35 ? 1 - ((t - 0.35) / 0.2).coerceIn(0, 1) : 1
        let horizontal = abs(b.y1 - b.y0) < abs(b.x1 - b.x0)
        let ax = b.ox + (b.x0 - b.ox) * grow
        let ay = b.oy + (b.y0 - b.oy) * grow
        let bx = b.ox + (b.x1 - b.ox) * grow
        let by = b.oy + (b.y1 - b.oy) * grow
        let th = b.thick * (0.7 + 0.3 * fade)
        func pill(_ thick: Float, _ shading: GraphicsContext.Shading) {
            let rect: CGRect
            if horizontal {
                rect = CGRect(x: CGFloat(ax - thick / 2), y: CGFloat(ay - thick / 2), width: CGFloat(bx - ax + thick), height: CGFloat(thick))
            } else {
                rect = CGRect(x: CGFloat(ax - thick / 2), y: CGFloat(ay - thick / 2), width: CGFloat(thick), height: CGFloat(by - ay + thick))
            }
            let r = rect.standardized
            ctx.fill(Path(roundedRect: r, cornerRadius: min(CGFloat(thick / 2), min(r.width, r.height) / 2), style: .circular), with: shading)
        }
        pill(th * 1.6, b.color.shading(alpha: 0.28 * fade))
        pill(th, b.color.shading(alpha: 0.7 * fade))
        pill(th * 0.42, RGBA.white.shading(alpha: 0.95 * fade))
    }

    private func drawZap(_ ctx: GraphicsContext, _ z: Zap) {
        let t = (time - z.start) / 0.4
        let flicker: Float = Kt.iadd(Kt.toInt(time * 40), z.seed) % 3 == 0 ? 0.45 : 1
        let a = (1 - t).coerceIn(0, 1) * flicker
        zapRnd.setSeed(Int64(z.seed) + Int64(Kt.toInt(time * 30)))
        let dx = z.x1 - z.x0
        let dy = z.y1 - z.y0
        let len = (dx * dx + dy * dy).squareRoot().coerceAtLeast(1)
        let nx = -dy / len
        let ny = dx / len
        var path = Path()
        path.move(to: CGPoint(x: CGFloat(z.x0), y: CGFloat(z.y0)))
        let segs = 7
        for i in 1..<segs {
            let f = Float(i) / Float(segs)
            let j = (zapRnd.nextFloat() - 0.5) * len * 0.12
            path.addLine(to: CGPoint(x: CGFloat(z.x0 + dx * f + nx * j), y: CGFloat(z.y0 + dy * f + ny * j)))
        }
        path.addLine(to: CGPoint(x: CGFloat(z.x1), y: CGFloat(z.y1)))
        ctx.stroke(path, with: Self.ZapGlow.shading(alpha: 0.5 * a), style: StrokeStyle(lineWidth: CGFloat(9 * k), lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: RGBA.white.shading(alpha: a), style: StrokeStyle(lineWidth: CGFloat(3 * k), lineCap: .round, lineJoin: .round))
    }

    private func drawFloatText(_ ctx: GraphicsContext, _ ft: FloatText) {
        let t = time - ft.start
        let tp = ft.text
        let w = Float(tp.size.width)
        let h = Float(tp.size.height)
        let outline = StrokeStyle(lineWidth: CGFloat((ft.kind == Self.T_SCORE ? 5 : 8) * k), lineJoin: .round)
        if ft.kind == Self.T_SCORE {
            let p = (t / ft.life).coerceIn(0, 1)
            let y = ft.y - 140 * k * Easing.outCubic(p)
            let a: Float = p > 0.5 ? 1 - (p - 0.5) / 0.5 : 1
            var c = ctx
            c.translateBy(x: CGFloat(ft.x - w / 2), y: CGFloat(y - h / 2))
            c.stroke(tp.path, with: Self.PlumOutline.shading(alpha: a), style: outline)
            c.fill(tp.path, with: ft.color.shading(alpha: ft.color.a * a))
        } else {
            let inT: Float = 0.38
            let outStart = ft.life - 0.28
            let sc: Float
            if t < inT { sc = Easing.outElastic(t / inT) }
            else if t > outStart { sc = 1 - Easing.inQuad(((t - outStart) / 0.28).coerceIn(0, 1)) }
            else { sc = 1 }
            let rot: Float = ft.kind == Self.T_PRAISE ? -6 + Kt.sin(t * 6) * 3 : 0
            let s = CGFloat(sc.coerceAtLeast(0.001))
            var c = ctx
            c.translateBy(x: CGFloat(ft.x), y: CGFloat(ft.y))
            c.rotate(by: .degrees(Double(rot)))
            c.scaleBy(x: s, y: s)
            c.translateBy(x: CGFloat(-w / 2), y: CGFloat(-h / 2))
            c.stroke(tp.path, with: Self.PlumOutline.shading, style: outline)
            if ft.kind == Self.T_PRAISE {
                c.fill(tp.path, with: .linearGradient(Self.PraiseGradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: CGFloat(h))))
            } else {
                c.fill(tp.path, with: ft.color.shading)
            }
        }
    }
}
