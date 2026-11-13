import SwiftUI
import GameKit

/**
 * Episode chest after the last level of an episode: the chest shakes harder and harder, bursts open with rays and
 * confetti, and shows its reward (100 coins + 1 random booster, already saved when the level was won).
 */
struct ChestDialog: View {
    let visible: Bool
    let reward: ChestReward?
    let onCollect: () -> Void

    @Environment(\.palette) private var p
    @State private var last: ChestReward?
    @State private var fx = DialogFx()
    @State private var start = Date()
    @State private var opened = false
    @State private var chestCenter: CGPoint = .zero

    /// Shake starts / chest opens (seconds after the dialog appears).
    private static let SHAKE_AT: Double = 0.45
    private static let OPEN_AT: Double = 1.75

    var body: some View {
        ZStack {
            if let r = reward ?? last {
                dialog(r)
            }
        }
        .onChange(of: reward, initial: true) { _, r in
            if let r { last = r }
        }
    }

    private func dialog(_ r: ChestReward) -> some View {
        let fx = self.fx
        let episodeName = LevelCatalog.episodeName(r.episode - 1)
        return SweetDialog(visible, onDismissRequest: {}, title: "Episode Complete!", ribbonColor: p.success) {
            BodyText("\(episodeName) cleared!", color: p.subText, fontSize: TypeScale.Label)
            ZStack {
                if opened {
                    PrizeRays()
                        .frame(width: 250, height: 250)
                        .transition(.scale(scale: 0.3).combined(with: .opacity).animation(.timingCurve(0, 0, 0.2, 1, duration: 0.5)))
                }
                ChestStage(start: start, shakeAt: Self.SHAKE_AT, openAt: Self.OPEN_AT, active: visible, opened: opened)
                    .frame(width: 190, height: 160)
                    .onGeometryChange(for: CGPoint.self) { proxy in
                        let f = proxy.frame(in: .global)
                        return CGPoint(x: f.midX, y: f.midY)
                    } action: { chestCenter = $0 }
            }
            .frame(height: 176)
            HStack(spacing: 18) {
                RewardChip(text: "+\(r.coins)") { CoinIcon(size: 30) }
                RewardChip(text: "+1 \(r.booster.shortName)") { BoosterIcon(r.booster, size: 30).frame(width: 34, height: 34) }
            }
            .scaleEffect(opened ? 1 : 0.3)
            .opacity(opened ? 1 : 0)
            Spacer().frame(height: 16)
            CandyButton3D("Collect", onClick: onCollect, color: p.gold, icon: Icons.Check, enabled: opened, breathing: opened)
        } front: {
            DialogFxCanvas(model: fx)
        }
        .onChange(of: visible, initial: true) { _, v in
            if v {
                opened = false
                start = Date()
            }
        }
        .task(id: visible) { await run() }
        .onDisappear { fx.stop() }
    }

    /// Shake ticks, then the burst: sounds, haptics, confetti, reward pop.
    private func run() async {
        guard visible else {
            fx.stop()
            return
        }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            opened = false
            start = Date()
        }
        let begin = ContinuousClock.now
        // Thuds on the shake peaks, getting faster.
        let thuds: [Double] = [0.5, 0.82, 1.08, 1.28, 1.44, 1.58]
        for (i, at) in thuds.enumerated() {
            try? await Task.sleep(until: begin.advanced(by: .milliseconds(Int(at * 1000))), clock: .continuous)
            if Task.isCancelled { return }
            AudioManager.shared.play(.LAND, rate: 0.85 + Float(i) * 0.08, volume: 0.8)
            Haptics.shared.light()
        }
        try? await Task.sleep(until: begin.advanced(by: .milliseconds(Int(Self.OPEN_AT * 1000))), clock: .continuous)
        if Task.isCancelled { return }
        AudioManager.shared.play(.WRAPPED, volume: 0.8)
        AudioManager.shared.play(.UNLOCK)
        Haptics.shared.heavy()
        fx.confetti()
        fx.sparkles(atGlobal: chestCenter, 16)
        withAnimation(.compose(dampingRatio: 0.5, stiffness: 380)) { opened = true }
    }
}

private struct RewardChip<Leading: View>: View {
    let text: String
    let leading: Leading

    @Environment(\.palette) private var p

    init(text: String, @ViewBuilder leading: () -> Leading) {
        self.text = text
        self.leading = leading()
    }

    var body: some View {
        HStack(spacing: 6) {
            leading
            OutlinedText(text, fontSize: 18, color: p.text, outline: p.cardBorder, outlineWidth: 1.5, shadow: false, maxLines: 1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: 44)
        .background(Capsule(style: .circular).fill(p.panelAlt))
        .overlay(Capsule(style: .circular).strokeBorder(p.cardBorder, lineWidth: 2))
        .fixedSize()
    }
}

/// The chest itself, timed from [start]: idle bob, shaking, then the lid flying open.
private struct ChestStage: View {
    let start: Date
    let shakeAt: Double
    let openAt: Double
    let active: Bool
    /// The lid only opens once the dialog says so (in step with the sounds and the reward pop).
    let opened: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let reduce = reduceMotion || Motion.reduce
        TimelineView(.animation(minimumInterval: nil, paused: !active)) { tl in
            let raw = max(0, tl.date.timeIntervalSince(start))
            let t = opened ? max(raw, openAt) : min(raw, openAt - 0.001)
            Canvas { ctx, size in
                ChestPaint.draw(ctx, size, t: t, shakeAt: shakeAt, openAt: openAt, reduce: reduce)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum ChestPaint {
    static let ink = RGBA(argb: 0xFF4A1C6E)
    static let body = Gradient(colors: [Color(argb: 0xFFFF7AB8), Color(argb: 0xFFE0306E)])
    static let lid = Gradient(colors: [Color(argb: 0xFFFF9CCB), Color(argb: 0xFFF04C8C)])
    static let gold = Gradient(colors: [Color(argb: 0xFFFFF1A8), Color(argb: 0xFFFFC12E), Color(argb: 0xFFE89211)])
    static let inside = Gradient(colors: [Color(argb: 0xFFFFF4B0), Color(argb: 0xFFFFB020).opacity(0)])

    static func draw(_ ctx: GraphicsContext, _ size: CGSize, t: Double, shakeAt: Double, openAt: Double, reduce: Bool) {
        let w = min(size.width, size.height * 1.2) * 0.78
        let cx = size.width / 2
        let baseY = size.height * 0.92
        // Shake: growing wobble with little hops.
        var rot = 0.0
        var hop: CGFloat = 0
        if t >= shakeAt && t < openAt {
            let k = (t - shakeAt) / (openAt - shakeAt)
            let amp = reduce ? 2.0 : 3 + 9 * k
            rot = Foundation.sin((t - shakeAt) * (reduce ? 20 : 34 + 22 * k)) * amp
            hop = reduce ? 0 : CGFloat(abs(Foundation.sin((t - shakeAt) * 17))) * w * 0.04 * CGFloat(k)
        } else if t < shakeAt && !reduce {
            hop = CGFloat(abs(Foundation.sin(t * 5))) * w * 0.015
        }
        let open = t >= openAt ? min(1, (t - openAt) / 0.38) : 0
        // Ease-out-back for the lid.
        let s = 1.7
        let u = open - 1
        let lidK = open > 0 ? 1 + (s + 1) * u * u * u + s * u * u : 0

        // Shadow on the floor.
        let shW = w * (1 - Double(hop / w) * 1.5)
        ctx.fill(Path(ellipseIn: CGRect(x: cx - shW * 0.55, y: baseY - w * 0.05, width: shW * 1.1, height: w * 0.12)),
                 with: RGBA(argb: 0xFF2A0B3D).shading(alpha: 0.22))

        var g = ctx
        g.translateBy(x: cx, y: baseY - hop)
        g.rotate(by: .degrees(rot))
        // Box: bottom at y = 0, top edge at −0.5w.
        let boxTop = -w * 0.5
        let box = Path(roundedRect: CGRect(x: -w / 2, y: boxTop, width: w, height: w * 0.5), cornerRadius: w * 0.07, style: .circular)
        let inkS = ink.shading(alpha: 0.8)
        g.stroke(box, with: inkS, lineWidth: w * 0.04)
        if open > 0 {
            // Glowing inside.
            let rim = Path(ellipseIn: CGRect(x: -w * 0.46, y: boxTop - w * 0.06, width: w * 0.92, height: w * 0.14))
            g.fill(rim, with: RGBA(argb: 0xFF5B1A4A).shading)
            var glow = g
            glow.opacity = open
            glow.fill(Path(ellipseIn: CGRect(x: -w * 0.7, y: boxTop - w * 0.7, width: w * 1.4, height: w * 0.9)),
                      with: .radialGradient(inside, center: CGPoint(x: 0, y: boxTop), startRadius: 0, endRadius: w * 0.7))
            // Coins peeking out.
            for (dx, dy) in [(-0.2, -0.02), (0.05, -0.06), (0.24, -0.01)] {
                g.drawCoin(w * dx, boxTop + w * dy, w * 0.09)
            }
        }
        g.fill(box, with: .linearGradient(body, startPoint: CGPoint(x: 0, y: boxTop), endPoint: CGPoint(x: 0, y: 0)))
        // Gold bands, trim and lock.
        let goldS = GraphicsContext.Shading.linearGradient(gold, startPoint: CGPoint(x: 0, y: boxTop), endPoint: CGPoint(x: 0, y: 0))
        for x in [-0.32, 0.32] {
            g.fill(Path(CGRect(x: w * x - w * 0.055, y: boxTop, width: w * 0.11, height: w * 0.5)), with: goldS)
        }
        g.fill(Path(roundedRect: CGRect(x: -w / 2, y: -w * 0.08, width: w, height: w * 0.08), cornerRadius: w * 0.04), with: goldS)
        g.fill(Path(roundedRect: CGRect(x: -w * 0.08, y: boxTop + w * 0.04, width: w * 0.16, height: w * 0.18), cornerRadius: w * 0.04), with: goldS)
        g.stroke(Path(roundedRect: CGRect(x: -w * 0.08, y: boxTop + w * 0.04, width: w * 0.16, height: w * 0.18), cornerRadius: w * 0.04), with: inkS, lineWidth: w * 0.02)
        g.fill(Path(ellipseIn: CGRect(x: -w * 0.025, y: boxTop + w * 0.09, width: w * 0.05, height: w * 0.05)), with: ink.shading)
        g.fill(Path(CGRect(x: -w * 0.012, y: boxTop + w * 0.12, width: w * 0.024, height: w * 0.05)), with: ink.shading)
        g.fill(Path(roundedRect: CGRect(x: -w * 0.42, y: boxTop + w * 0.05, width: w * 0.2, height: w * 0.04), cornerRadius: w * 0.02), with: RGBA.white.shading(alpha: 0.4))

        // Lid: hinged at the back, flies up and tilts.
        var l = g
        l.translateBy(x: -w * 0.08 * lidK, y: boxTop - w * 0.42 * lidK)
        l.rotate(by: .degrees(-18 * lidK))
        let lidH = w * 0.3
        var lidPath = Path()
        lidPath.addRoundedRect(in: CGRect(x: -w * 0.52, y: -lidH, width: w * 1.04, height: lidH),
                               cornerSize: CGSize(width: w * 0.1, height: w * 0.1), style: .circular)
        l.stroke(lidPath, with: inkS, lineWidth: w * 0.04)
        l.fill(lidPath, with: .linearGradient(lid, startPoint: CGPoint(x: 0, y: -lidH), endPoint: .zero))
        for x in [-0.32, 0.32] {
            l.fill(Path(CGRect(x: w * x - w * 0.055, y: -lidH, width: w * 0.11, height: lidH)), with: goldS)
        }
        l.fill(Path(roundedRect: CGRect(x: -w * 0.52, y: -w * 0.07, width: w * 1.04, height: w * 0.07), cornerRadius: w * 0.035), with: goldS)
        l.fill(Path(roundedRect: CGRect(x: -w * 0.4, y: -lidH + w * 0.05, width: w * 0.3, height: w * 0.05), cornerRadius: w * 0.025), with: RGBA.white.shading(alpha: 0.45))
    }
}
