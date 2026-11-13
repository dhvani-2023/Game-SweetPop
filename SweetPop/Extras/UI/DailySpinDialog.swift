import SwiftUI
import GameKit

/**
 * Daily Spin (once per local day): an 8-segment prize wheel that spins up and decelerates smoothly onto a prize
 * chosen up front (weighted, see `DailySpin`), ticking with a sound + haptic at every segment, then confetti.
 * The spin and its prize are saved the moment it starts, so closing the app mid-spin can't re-roll it.
 */
struct DailySpinDialog: View {
    let visible: Bool
    /// Closed; the prize just won (if any) so the map can celebrate it (coins fly into the pill).
    let onClose: (DailySpin.Prize?) -> Void

    @Environment(\.palette) private var p
    @Environment(AppContainer.self) private var container
    @State private var model = SpinWheelModel()
    @State private var fx = DialogFx()
    @State private var phase: Phase = .ready
    @State private var won: Int?
    @State private var wheelCenter: CGPoint = .zero

    private enum Phase { case ready, spinning, won, used }

    var body: some View {
        let model = self.model
        let fx = self.fx
        SweetDialog(
            visible, onDismissRequest: { if phase != .spinning { close() } }, title: "Daily Spin", ribbonColor: p.accent,
            showClose: phase == .ready || phase == .used
        ) {
            SpinWheel(model: model, highlight: phase == .won ? won : nil)
                .frame(width: 264, height: 282)
                .onGeometryChange(for: CGPoint.self) { proxy in
                    let f = proxy.frame(in: .global)
                    return CGPoint(x: f.midX, y: f.minY + 30)
                } action: { wheelCenter = $0 }
            Spacer().frame(height: 6)
            footer
        } front: {
            DialogFxCanvas(model: fx)
        }
        .onChange(of: visible, initial: true) { _, v in
            if v { prepare() } else { fx.stop() }
        }
        .onDisappear {
            fx.stop()
            model.stop()
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch phase {
        case .ready:
            BodyText("Spin once a day for a sweet prize!", color: p.text)
            Spacer().frame(height: 14)
            CandyButton3D("Spin!", onClick: spin, color: p.success, icon: Icons.Refresh, breathing: true)
        case .spinning:
            BodyText("Good luck!", color: p.text)
            Spacer().frame(height: 14)
            CandyButton3D("Spinning…", onClick: {}, color: p.success, enabled: false)
        case .won:
            let prize = won.map { DailySpin.segments[$0].prize }
            OutlinedText(
                prize.map { "You won \(DailySpin.label($0))!" } ?? "", fontSize: TypeScale.Body + 4, color: p.gold,
                outline: shade(p.gold, 0.45), outlineWidth: 2.5
            )
            Spacer().frame(height: 14)
            CandyButton3D("Collect", onClick: close, color: p.gold, icon: Icons.Check, breathing: true)
        case .used:
            BodyText("Next spin in", color: p.text)
            TimelineView(.periodic(from: .now, by: 1)) { tl in
                OutlinedText(Self.untilTomorrow(tl.date), fontSize: TypeScale.Title, color: p.accent, outline: shade(p.accent, 0.5), outlineWidth: 2.5)
            }
            Spacer().frame(height: 14)
            CandyButton3D("OK", onClick: close, color: p.success)
        }
    }

    private func prepare() {
        won = nil
        let today = Days.epochDay()
        phase = DailySpin.isAvailable(spinDay: container.save.extras.spinDay, today: today) ? .ready : .used
        model.onTick = {
            AudioManager.shared.play(.CLICK, rate: 1.25, volume: 0.45)
            if Haptics.shared.enabled { GameKit.Haptics.tick() }
        }
    }

    private func spin() {
        guard phase == .ready else { return }
        let save = container.save
        let today = Days.epochDay()
        guard DailySpin.isAvailable(spinDay: save.extras.spinDay, today: today) else {
            phase = .used
            return
        }
        let index = DailySpin.pick(roll: Double.random(in: 0..<1), livesFull: save.state.livesNow().isFull)
        let prize = DailySpin.segments[index].prize
        save.recordSpin(day: today, prize: prize)
        if Features.economy, case .coins(let n) = prize { container.extras.coinsInFlight += n }
        won = index
        phase = .spinning
        AudioManager.shared.play(.WHOOSH, volume: 0.6)
        let reduce = Motion.reduce
        let fx = self.fx
        let center = wheelCenter
        model.onStop = {
            phase = .won
            fx.confetti()
            fx.sparkles(atGlobal: center, 14)
            AudioManager.shared.play(.UNLOCK)
            if case .coins(let n) = prize, n >= 100 { AudioManager.shared.play(.WIN, volume: 0.7) }
            Haptics.shared.heavy()
        }
        model.spin(to: index, duration: reduce ? 1.6 : 4.8, turns: reduce ? 1 : 5)
    }

    private func close() {
        let prize = phase == .won ? won.map { DailySpin.segments[$0].prize } : nil
        onClose(prize)
    }

    /// "HH:MM:SS" until local midnight.
    static func untilTomorrow(_ now: Date) -> String {
        let cal = Calendar.current
        let next = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let s = max(0, Int(next.timeIntervalSince(now)))
        func two(_ v: Int) -> String { v < 10 ? "0\(v)" : String(v) }
        return "\(two(s / 3600)):\(two(s / 60 % 60)):\(two(s % 60))"
    }
}

// MARK: - Wheel model

/// Wheel angle on its own frame loop: an ease-out-quart spin to a target segment, one tick per segment passed.
@MainActor
@Observable
final class SpinWheelModel {
    /// Clockwise rotation in degrees (segment i sits under the pointer at −i × 45°).
    private(set) var angle: Double = 0
    /// Pointer flick (1 → 0) after each tick.
    private(set) var kick: Double = 0
    private(set) var spinning = false

    @ObservationIgnored var onTick: (() -> Void)?
    @ObservationIgnored var onStop: (() -> Void)?
    @ObservationIgnored private let loop = GameLoop()
    @ObservationIgnored private var from = 0.0
    @ObservationIgnored private var to = 0.0
    @ObservationIgnored private var elapsed = 0.0
    @ObservationIgnored private var duration = 4.8
    @ObservationIgnored private var lastBoundary = 0
    @ObservationIgnored private var lastTickAt = -1.0

    init() {
        loop.maxDelta = 0.05
        loop.onTick = { [weak self] dt in self?.step(dt) }
    }

    func spin(to index: Int, duration: Double, turns: Int) {
        let sweep = DailySpin.sweep
        from = angle.truncatingRemainder(dividingBy: 360)
        angle = from
        let target = -Double(index) * sweep + Double.random(in: -sweep * 0.3...sweep * 0.3)
        var delta = (target - from).truncatingRemainder(dividingBy: 360)
        if delta < 0 { delta += 360 }
        to = from + Double(turns) * 360 + delta
        elapsed = 0
        self.duration = duration
        lastBoundary = boundary(from)
        lastTickAt = -1
        spinning = true
        loop.start()
    }

    func stop() { loop.stop() }

    private func boundary(_ a: Double) -> Int { Int(((a + DailySpin.sweep / 2) / DailySpin.sweep).rounded(.down)) }

    private func step(_ dt: Double) {
        elapsed += dt
        kick *= Foundation.exp(-dt * 11)
        guard spinning else {
            if kick < 0.01 {
                kick = 0
                loop.stop()
            }
            return
        }
        let k = min(1, elapsed / duration)
        let e = 1 - Foundation.pow(1 - k, 4)
        angle = from + (to - from) * e
        let b = boundary(angle)
        if b != lastBoundary {
            lastBoundary = b
            kick = 1
            // Fast spins pass ~30 segments a second: keep ticks at most 20 a second.
            if elapsed - lastTickAt >= 0.05 {
                lastTickAt = elapsed
                onTick?()
            }
        }
        if k >= 1 {
            spinning = false
            onStop?()
        }
    }
}

// MARK: - Wheel views

private let WHEEL_R: CGFloat = 112
private let RING_W: CGFloat = 16

private struct SpinWheel: View {
    let model: SpinWheelModel
    let highlight: Int?

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let angle = model.angle
        let kick = model.kick
        let size = (WHEEL_R + RING_W) * 2
        ZStack(alignment: .top) {
            ZStack {
                WheelRing(spinning: model.spinning)
                WheelFace(decor: decorBitmapPx(displayScale))
                    .equatable()
                    .frame(width: WHEEL_R * 2, height: WHEEL_R * 2)
                    .rotationEffect(.degrees(angle))
                if highlight != nil { WinnerGlow() }
                WheelHub()
            }
            .frame(width: size, height: size)
            .padding(.top, 22)
            WheelPointer()
                .frame(width: 38, height: 48)
                .rotationEffect(.degrees(-kick * 24), anchor: UnitPoint(x: 0.5, y: 0.2))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Prize wheel")
    }
}

/// The eight prize wedges (drawn once; the parent rotates it).
private struct WheelFace: View, Equatable {
    let decor: Int

    nonisolated static func == (a: WheelFace, b: WheelFace) -> Bool { a.decor == b.decor }

    var body: some View {
        let decor = self.decor
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let sweep = DailySpin.sweep
            for (i, seg) in DailySpin.segments.enumerated() {
                let mid = Double(i) * sweep - 90
                let wedge = wedgePath(c, r, mid - sweep / 2, mid + sweep / 2)
                let col = RGBA(argb: seg.argb)
                ctx.fill(wedge, with: .radialGradient(
                    Gradient(colors: [lightenRGBA(col, 0.45).color, col.color]), center: c, startRadius: 0, endRadius: r
                ))
                // Content upright along the wedge's axis.
                var g = ctx
                g.translateBy(x: c.x, y: c.y)
                g.rotate(by: .degrees(Double(i) * sweep))
                drawPrize(g, seg.prize, r, decor)
            }
            // Spokes and rim.
            var spokes = Path()
            for i in 0..<DailySpin.count {
                let a = (Double(i) * sweep - 90 - sweep / 2) * Double.pi / 180
                spokes.move(to: c)
                spokes.addLine(to: CGPoint(x: c.x + r * CGFloat(Foundation.cos(a)), y: c.y + r * CGFloat(Foundation.sin(a))))
            }
            ctx.stroke(spokes, with: RGBA.white.shading(alpha: 0.9), lineWidth: 3)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: RGBA.white.shading, lineWidth: 3)
        }
    }

    private func drawPrize(_ g: GraphicsContext, _ prize: DailySpin.Prize, _ r: CGFloat, _ decor: Int) {
        switch prize {
        case .coins(let n):
            g.drawCoin(0, -r * 0.66, r * 0.13)
            label(g, String(n), y: -r * 0.4, size: 19)
        case .booster(let b):
            g.drawBoosterIcon(b, 0, -r * 0.6, r * 0.34, bitmapPx: decor)
        case .life:
            let s = r * 0.27
            g.drawIcon(Icons.Heart, in: CGRect(x: -s / 2, y: -r * 0.66 - s / 2, width: s, height: s), tint: HeartRed)
            label(g, "+1", y: -r * 0.4, size: 19)
        }
    }

    private func label(_ g: GraphicsContext, _ text: String, y: CGFloat, size: CGFloat) {
        let tp = TextPaths.layout(text, fontSize: size)
        var t = g
        t.translateBy(x: -tp.size.width / 2, y: y - tp.size.height / 2)
        t.stroke(tp.path, with: RGBA(argb: 0xFF4A1C6E).shading(alpha: 0.85), style: StrokeStyle(lineWidth: 4.5, lineJoin: .round))
        t.fill(tp.path, with: .color(.white))
    }
}

/// A pie wedge as a polyline (independent of arc-direction conventions).
private func wedgePath(_ c: CGPoint, _ r: CGFloat, _ fromDeg: Double, _ toDeg: Double) -> Path {
    var p = Path()
    p.move(to: c)
    let steps = 18
    for i in 0...steps {
        let a = (fromDeg + (toDeg - fromDeg) * Double(i) / Double(steps)) * Double.pi / 180
        p.addLine(to: CGPoint(x: c.x + r * CGFloat(Foundation.cos(a)), y: c.y + r * CGFloat(Foundation.sin(a))))
    }
    p.closeSubpath()
    return p
}

/// Candy ring with 16 bulbs that chase while spinning and twinkle otherwise.
private struct WheelRing: View {
    let spinning: Bool

    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ringA = p.accent
        let ringB = p.accent2
        let still = reduceMotion || Motion.reduce
        TimelineView(.periodic(from: .now, by: spinning ? 0.09 : 0.45)) { tl in
            let step = still ? 0 : Int(tl.date.timeIntervalSinceReferenceDate / (spinning ? 0.09 : 0.45))
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let outer = min(size.width, size.height) / 2
                let mid = outer - RING_W / 2
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - outer - 3, y: c.y - outer + 3, width: (outer + 3) * 2, height: (outer + 3) * 2)),
                         with: RGBA(argb: 0xFF2A0B3D).shading(alpha: 0.28))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2)),
                         with: .linearGradient(Gradient(colors: [lighten(ringA, 0.15), ringB]), startPoint: CGPoint(x: c.x, y: c.y - outer), endPoint: CGPoint(x: c.x, y: c.y + outer)))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - outer + 1.5, y: c.y - outer + 1.5, width: outer * 2 - 3, height: outer * 2 - 3)),
                           with: RGBA.white.shading(alpha: 0.85), lineWidth: 3)
                for i in 0..<16 {
                    let a = Double(i) * Double.pi / 8 - Double.pi / 2
                    let x = c.x + mid * CGFloat(Foundation.cos(a))
                    let y = c.y + mid * CGFloat(Foundation.sin(a))
                    let lit = spinning ? (i + step) % 4 == 0 : (i + step) % 2 == 0
                    let br: CGFloat = 4.2
                    if lit {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - br * 2.2, y: y - br * 2.2, width: br * 4.4, height: br * 4.4)),
                                 with: .radialGradient(Gradient(colors: [Color(argb: 0xFFFFF4B0).opacity(0.85), .clear]),
                                                       center: CGPoint(x: x, y: y), startRadius: 0, endRadius: br * 2.2))
                    }
                    ctx.fill(Path(ellipseIn: CGRect(x: x - br, y: y - br, width: br * 2, height: br * 2)),
                             with: lit ? RGBA(argb: 0xFFFFF8D6).shading : RGBA(argb: 0xFFFFD3EC).shading(alpha: 0.75))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Gold hub with a star.
private struct WheelHub: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r: CGFloat = 26
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r + 3, width: r * 2, height: r * 2)), with: RGBA(argb: 0xFF9A5200).shading(alpha: 0.5))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                     with: .linearGradient(Gradient(colors: [Color(argb: 0xFFFFF1A8), Color(argb: 0xFFFFC12E), Color(argb: 0xFFFF9E1B)]),
                                           startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: RGBA.white.shading, lineWidth: 3)
            ctx.drawStar(c.x, c.y + 1, r * 0.55, true)
        }
        .frame(width: 70, height: 70)
        .allowsHitTesting(false)
    }
}

/// Candy-pink pointer at the top (pivots near its top when flicked).
private struct WheelPointer: View {
    @Environment(\.palette) private var p

    var body: some View {
        let color = p.danger
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            var drop = Path()
            drop.move(to: CGPoint(x: w / 2, y: h))
            drop.addCurve(to: CGPoint(x: w / 2, y: 2), control1: CGPoint(x: -w * 0.25, y: h * 0.42), control2: CGPoint(x: w * 0.05, y: 2))
            drop.addCurve(to: CGPoint(x: w / 2, y: h), control1: CGPoint(x: w * 0.95, y: 2), control2: CGPoint(x: w * 1.25, y: h * 0.42))
            drop.closeSubpath()
            var sh = ctx
            sh.translateBy(x: 0, y: 3)
            sh.fill(drop, with: RGBA(argb: 0xFF2A0B3D).shading(alpha: 0.3))
            ctx.fill(drop, with: .linearGradient(Gradient(colors: [lighten(color, 0.2), shade(color, 0.85)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            ctx.stroke(drop, with: RGBA.white.shading, lineWidth: 3)
            ctx.fill(Path(ellipseIn: CGRect(x: w / 2 - 6, y: h * 0.26, width: 12, height: 12)), with: RGBA.white.shading(alpha: 0.9))
        }
        .allowsHitTesting(false)
    }
}

/// Pulsing glow over the winning wedge (always the one under the pointer).
private struct WinnerGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let still = reduceMotion || Motion.reduce
        ClockView(paused: still) { t in
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let a = still ? 0.3 : 0.22 + 0.16 * Foundation.sin(Double(t) * 6)
                let sweep = DailySpin.sweep
                let wedge = wedgePath(c, WHEEL_R, -90 - sweep / 2, -90 + sweep / 2)
                ctx.fill(wedge, with: RGBA.white.shading(alpha: Float(a)))
                ctx.stroke(wedge, with: RGBA(argb: 0xFFFFF4B0).shading, style: StrokeStyle(lineWidth: 4, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
    }
}
