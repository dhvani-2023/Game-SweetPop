import SwiftUI
import GameKit

// Procedural art of the extras, drawn like the rest of the game (GraphicsContext paths, unit shapes built once):
// coin, booster icons (lollipop hammer, swap, +5), gift box, prize-wheel badge, and the "eye" settings icon.

private enum CoinPaint {
    static let unit = Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2))
    static let face = Path(ellipseIn: CGRect(x: -0.8, y: -0.8, width: 1.6, height: 1.6))
    static let ring = Path(ellipseIn: CGRect(x: -0.62, y: -0.62, width: 1.24, height: 1.24))
    static let star = starPath(0, 0.03, 0.44, inner: 0.47)
    static let shine = Path(ellipseIn: CGRect(x: -0.62, y: -0.66, width: 0.62, height: 0.3))
    static let lip = RGBA(argb: 0xFF9A5200)
    static let ink = RGBA(argb: 0xFFB8650A)
    static let rim = Gradient(colors: [Color(argb: 0xFFFFD45A), Color(argb: 0xFFD98A0B), Color(argb: 0xFFB86400)])
    static let body = Gradient(colors: [Color(argb: 0xFFFFF6B8), Color(argb: 0xFFFFCD3F), Color(argb: 0xFFFFA81F)])
    static let emblem = Gradient(colors: [Color(argb: 0xFFFFE680), Color(argb: 0xFFFFB52B)])
}

extension GraphicsContext {
    /// Gold coin with a star, centred at (cx, cy) with radius [r]. [flip] (−1…1) squashes it horizontally, for a
    /// coin spinning in flight.
    func drawCoin(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, flip: CGFloat = 1, alpha: Double = 1) {
        guard r > 0, alpha > 0 else { return }
        var g = self
        g.opacity *= alpha
        g.translateBy(x: cx, y: cy)
        g.scaleBy(x: r * max(0.1, abs(flip)), y: r)
        var lip = g
        lip.translateBy(x: 0, y: 0.1)
        lip.fill(CoinPaint.unit, with: CoinPaint.lip.shading)
        g.fill(CoinPaint.unit, with: .linearGradient(CoinPaint.rim, startPoint: CGPoint(x: 0, y: -1), endPoint: CGPoint(x: 0, y: 1)))
        g.fill(CoinPaint.face, with: .linearGradient(CoinPaint.body, startPoint: CGPoint(x: 0, y: -0.8), endPoint: CGPoint(x: 0, y: 0.8)))
        g.stroke(CoinPaint.ring, with: CoinPaint.ink.shading(alpha: 0.35), lineWidth: 0.07)
        if abs(flip) > 0.35 {
            g.stroke(CoinPaint.star, with: CoinPaint.ink.shading(alpha: 0.75), style: StrokeStyle(lineWidth: 0.1, lineJoin: .round))
            g.fill(CoinPaint.star, with: .linearGradient(CoinPaint.emblem, startPoint: CGPoint(x: 0, y: -0.45), endPoint: CGPoint(x: 0, y: 0.45)))
        }
        g.fill(CoinPaint.shine, with: RGBA.white.shading(alpha: 0.6))
    }
}

/// A coin icon laid out at [size] (drawn a little past its frame, like the star icons).
struct CoinIcon: View {
    let size: CGFloat

    init(size: CGFloat) {
        self.size = size
    }

    var body: some View {
        let s = size
        Canvas { ctx, cs in
            ctx.drawCoin(cs.width / 2, cs.height / 2 - s * 0.03, s * 0.44)
        }
        .frame(width: s * 1.2, height: s * 1.2)
        .padding(-s * 0.1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Booster icons

private enum BoosterPaint {
    static let head = Path(ellipseIn: CGRect(x: -0.32, y: -0.86, width: 1.04, height: 1.04))
    static let headCenter = CGPoint(x: 0.2, y: -0.34)
    static let headGradient = Gradient(colors: [Color(argb: 0xFFFF8CC6), Color(argb: 0xFFFF3D8B), Color(argb: 0xFFD81B6A)])
    /// Archimedean swirl inside the lollipop head.
    static let swirl: Path = {
        var p = Path()
        let turns = 2.3
        let steps = 70
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let a = t * turns * 2 * Double.pi
            let r = 0.04 + t * 0.42
            let pt = CGPoint(x: headCenter.x + CGFloat(r * Foundation.cos(a)), y: headCenter.y + CGFloat(r * Foundation.sin(a)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }()
    static let stick: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -0.05, y: -0.1))
        p.addLine(to: CGPoint(x: -0.66, y: 0.82))
        return p
    }()
    static let headShine = Path(ellipseIn: CGRect(x: -0.14, y: -0.74, width: 0.34, height: 0.2))
    static let stickShade = RGBA(argb: 0xFFC9B8DE)
    static let outline = RGBA(argb: 0xFF4A1C6E)

    static let arrowTop: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -0.55, y: -0.42))
        p.addQuadCurve(to: CGPoint(x: 0.5, y: -0.46), control: CGPoint(x: 0, y: -1.02))
        return p
    }()
    static let arrowBottom: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0.55, y: 0.5))
        p.addQuadCurve(to: CGPoint(x: -0.5, y: 0.54), control: CGPoint(x: 0, y: 1.08))
        return p
    }()
    static let headTop: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0.28, y: -0.68))
        p.addLine(to: CGPoint(x: 0.56, y: -0.42))
        p.addLine(to: CGPoint(x: 0.2, y: -0.3))
        p.closeSubpath()
        return p
    }()
    static let headBottom: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -0.28, y: 0.76))
        p.addLine(to: CGPoint(x: -0.56, y: 0.5))
        p.addLine(to: CGPoint(x: -0.2, y: 0.38))
        p.closeSubpath()
        return p
    }()
}

extension GraphicsContext {
    /// Booster icon centred at (cx, cy), [size] across. [bitmapPx] is the candy bitmap size for the swap icon.
    func drawBoosterIcon(_ b: Booster, _ cx: CGFloat, _ cy: CGFloat, _ size: CGFloat, bitmapPx: Int) {
        guard size > 0 else { return }
        switch b {
        case .HAMMER: drawLollipopHammer(cx, cy, size)
        case .SWAP:
            let cell = size * 0.5
            drawCandy(.BLUE, .NONE, cx - size * 0.25, cy + size * 0.03, cell, bitmapPx: bitmapPx)
            drawCandy(.RED, .NONE, cx + size * 0.25, cy + size * 0.03, cell, bitmapPx: bitmapPx)
            var g = self
            g.translateBy(x: cx, y: cy)
            g.scaleBy(x: size / 2, y: size / 2)
            let outline = BoosterPaint.outline.shading(alpha: 0.85)
            for (arc, head) in [(BoosterPaint.arrowTop, BoosterPaint.headTop), (BoosterPaint.arrowBottom, BoosterPaint.headBottom)] {
                g.stroke(arc, with: outline, style: StrokeStyle(lineWidth: 0.24, lineCap: .round))
                g.stroke(head, with: outline, style: StrokeStyle(lineWidth: 0.12, lineJoin: .round))
                g.stroke(arc, with: RGBA.white.shading, style: StrokeStyle(lineWidth: 0.12, lineCap: .round))
                g.fill(head, with: RGBA.white.shading)
            }
        case .MOVES:
            let tp = TextPaths.layout("+5", fontSize: 40)
            let k = size * 0.82 / max(tp.size.width, tp.size.height * 0.9, 1)
            var g = self
            g.translateBy(x: cx - tp.size.width * k / 2, y: cy - tp.size.height * k / 2)
            g.scaleBy(x: k, y: k)
            g.stroke(tp.path, with: BoosterPaint.outline.shading(alpha: 0.9), style: StrokeStyle(lineWidth: 7, lineJoin: .round))
            g.fill(tp.path, with: .linearGradient(Gradient(colors: [.white, Color(argb: 0xFFDFFFE9)]),
                                                  startPoint: .zero, endPoint: CGPoint(x: 0, y: tp.size.height)))
        }
    }

    /// A swirl lollipop held like a mallet.
    func drawLollipopHammer(_ cx: CGFloat, _ cy: CGFloat, _ size: CGFloat, rotationDeg: Double = 0) {
        var g = self
        g.translateBy(x: cx, y: cy)
        if rotationDeg != 0 { g.rotate(by: .degrees(rotationDeg)) }
        g.scaleBy(x: size / 2, y: size / 2)
        let outline = BoosterPaint.outline.shading(alpha: 0.8)
        g.stroke(BoosterPaint.stick, with: outline, style: StrokeStyle(lineWidth: 0.32, lineCap: .round))
        g.stroke(BoosterPaint.stick, with: BoosterPaint.stickShade.shading, style: StrokeStyle(lineWidth: 0.2, lineCap: .round))
        var hi = g
        hi.translateBy(x: -0.03, y: -0.02)
        hi.stroke(BoosterPaint.stick, with: RGBA.white.shading, style: StrokeStyle(lineWidth: 0.1, lineCap: .round))
        g.fill(BoosterPaint.head.insetBy(-0.08), with: outline)
        g.fill(BoosterPaint.head, with: .linearGradient(BoosterPaint.headGradient, startPoint: CGPoint(x: 0, y: -0.86), endPoint: CGPoint(x: 0, y: 0.18)))
        var sw = g
        sw.clip(to: BoosterPaint.head)
        sw.stroke(BoosterPaint.swirl, with: RGBA.white.shading(alpha: 0.92), style: StrokeStyle(lineWidth: 0.12, lineCap: .round))
        g.fill(BoosterPaint.headShine, with: RGBA.white.shading(alpha: 0.55))
    }
}

private extension Path {
    /// The ellipse grown by [d] on every side (paths here are simple ellipses).
    func insetBy(_ d: CGFloat) -> Path {
        let r = boundingRect.insetBy(dx: d, dy: d)
        return Path(ellipseIn: r)
    }
}

/// A booster icon laid out at [size].
struct BoosterIcon: View {
    let booster: Booster
    let size: CGFloat

    @Environment(\.displayScale) private var displayScale

    init(_ booster: Booster, size: CGFloat) {
        self.booster = booster
        self.size = size
    }

    var body: some View {
        let b = booster
        let s = size
        let decor = decorBitmapPx(displayScale)
        Canvas { ctx, cs in
            ctx.drawBoosterIcon(b, cs.width / 2, cs.height / 2, s, bitmapPx: decor)
        }
        .frame(width: s * 1.3, height: s * 1.3)
        .padding(-s * 0.15)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Gift box (login day 7) and wheel badge (map button)

private enum GiftPaint {
    static let box = Gradient(colors: [Color(argb: 0xFFB77BFF), Color(argb: 0xFF7B4DFF)])
    static let lid = Gradient(colors: [Color(argb: 0xFFD3A8FF), Color(argb: 0xFF9461FF)])
    static let ribbon = Gradient(colors: [Color(argb: 0xFFFFE27A), Color(argb: 0xFFFFB020)])
    static let ink = RGBA(argb: 0xFF4A1C6E)
}

extension GraphicsContext {
    /// Wrapped gift box with a gold bow, [size] across.
    func drawGiftBox(_ cx: CGFloat, _ cy: CGFloat, _ size: CGFloat) {
        var g = self
        g.translateBy(x: cx, y: cy)
        g.scaleBy(x: size / 2, y: size / 2)
        let ink = GiftPaint.ink.shading(alpha: 0.75)
        let body = Path(roundedRect: CGRect(x: -0.72, y: -0.18, width: 1.44, height: 0.98), cornerRadius: 0.14, style: .circular)
        let lid = Path(roundedRect: CGRect(x: -0.86, y: -0.44, width: 1.72, height: 0.34), cornerRadius: 0.12, style: .circular)
        g.stroke(body, with: ink, lineWidth: 0.12)
        g.stroke(lid, with: ink, lineWidth: 0.12)
        g.fill(body, with: .linearGradient(GiftPaint.box, startPoint: CGPoint(x: 0, y: -0.2), endPoint: CGPoint(x: 0, y: 0.8)))
        g.fill(lid, with: .linearGradient(GiftPaint.lid, startPoint: CGPoint(x: 0, y: -0.44), endPoint: CGPoint(x: 0, y: -0.1)))
        let ribbon = GraphicsContext.Shading.linearGradient(GiftPaint.ribbon, startPoint: CGPoint(x: 0, y: -0.9), endPoint: CGPoint(x: 0, y: 0.8))
        g.fill(Path(CGRect(x: -0.13, y: -0.44, width: 0.26, height: 1.24)), with: ribbon)
        // Bow: two loops.
        for s in [-1.0, 1.0] {
            var loop = Path()
            loop.move(to: CGPoint(x: 0, y: -0.46))
            loop.addCurve(to: CGPoint(x: 0, y: -0.46), control1: CGPoint(x: 0.62 * s, y: -1.05), control2: CGPoint(x: 0.75 * s, y: -0.42))
            g.stroke(loop, with: ink, lineWidth: 0.1)
            g.fill(loop, with: ribbon)
        }
        g.fill(Path(ellipseIn: CGRect(x: -0.13, y: -0.58, width: 0.26, height: 0.24)), with: ribbon)
        g.fill(Path(roundedRect: CGRect(x: -0.6, y: -0.38, width: 0.5, height: 0.08), cornerRadius: 0.04), with: RGBA.white.shading(alpha: 0.45))
    }

    /// Small prize wheel (map button face): 8 wedges, white spokes and a gold hub. [rotationDeg] spins it.
    func drawWheelBadge(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, rotationDeg: Double = 0) {
        var g = self
        g.translateBy(x: cx, y: cy)
        g.rotate(by: .degrees(rotationDeg))
        let n = DailySpin.count
        let sweep = DailySpin.sweep
        for i in 0..<n {
            var w = Path()
            w.move(to: .zero)
            w.addArc(center: .zero, radius: r, startAngle: .degrees(Double(i) * sweep - 90 - sweep / 2),
                     endAngle: .degrees(Double(i) * sweep - 90 + sweep / 2), clockwise: false)
            w.closeSubpath()
            g.fill(w, with: RGBA(argb: DailySpin.segments[i].argb).shading)
        }
        g.stroke(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: RGBA.white.shading, lineWidth: r * 0.16)
        g.fill(Path(ellipseIn: CGRect(x: -r * 0.3, y: -r * 0.3, width: r * 0.6, height: r * 0.6)), with: RGBA(argb: 0xFFFFC12E).shading)
        g.stroke(Path(ellipseIn: CGRect(x: -r * 0.3, y: -r * 0.3, width: r * 0.6, height: r * 0.6)), with: RGBA.white.shading, lineWidth: r * 0.08)
    }
}

// MARK: - Icons

enum ExtrasIcons {
    /// Material "visibility" (Settings › Colour-blind symbols).
    static let Eye = ImageVector(
        name: "eye", viewport: 24,
        paths: [.init(path: PathData.parse(
            "M12,4.5C7,4.5 2.73,7.61 1,12c1.73,4.39 6,7.5 11,7.5s9.27,-3.11 11,-7.5c-1.73,-4.39 -6,-7.5 -11,-7.5zM12,17c-2.76,0 -5,-2.24 -5,-5s2.24,-5 5,-5 5,2.24 5,5 -2.24,5 -5,5zM12,9c-1.66,0 -3,1.34 -3,3s1.34,3 3,3 3,-1.34 3,-3 -1.34,-3 -3,-3z"
        ), evenOdd: true)]
    )
}
