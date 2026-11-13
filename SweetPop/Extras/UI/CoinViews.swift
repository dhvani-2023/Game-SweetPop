import SwiftUI
import GameKit

// Coin UI: the map's coin pill (counts up), coins flying into it, the Win dialog's "+N coins" row and the
// coins info dialog (tap on the pill).

/// Glass chip with a coin, like the lives / stars chips; the number counts to [coins] whenever it changes and
/// the chip punches each time [bump] changes (a coin landed).
struct CoinPill: View {
    let coins: Int
    let bump: Int
    var onClick: (() -> Void)? = nil

    @State private var punch = 0

    var body: some View {
        CountingCoinChip(value: Double(coins), onClick: onClick)
            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.35), value: coins)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: punch) { content, s in
                content.scaleEffect(s, anchor: .leading)
            } keyframes: { _ in
                MoveKeyframe(CGFloat(1.14))
                SpringKeyframe(CGFloat(1), spring: composeSpring(dampingRatio: 0.45, stiffness: 520))
            }
            .onChange(of: bump) { _, _ in punch &+= 1 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(coins) coins")
            .accessibilityAddTraits(onClick != nil ? .isButton : [])
    }
}

private struct CountingCoinChip: View, Animatable {
    var value: Double
    let onClick: (() -> Void)?

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        GlassChip(GoalTracker.formatNumber(Int(value.rounded())), onClick: onClick) {
            CoinIcon(size: 34)
        }
    }
}

/**
 * Coins flying from a point into the coin pill: they burst out, then curve into the pill (which may move — the
 * target is re-read every frame). Driven by the owner's frame loop: call [update] every frame and [draw] from a
 * Canvas in the same coordinate space as [target]. [onArrive] reports each coin's share of the amount.
 */
@MainActor
final class CoinShower {
    private struct Coin {
        let x0: Float, y0: Float
        /// Burst point the coin flies out to before heading for the pill.
        let bx: Float, by: Float
        let start: Float
        let dur: Float
        let spin: Float
        let value: Int
    }

    private var coins: [Coin] = []
    private(set) var time: Float = 0
    /// Pill coin centre, in the canvas's coordinates.
    var target: CGPoint = .zero
    var onArrive: ((_ value: Int, _ last: Bool) -> Void)?

    init() {
        coins.reserveCapacity(16)
    }

    var isBusy: Bool { !coins.isEmpty }

    /// Launches [amount] coins' worth (4…12 sprites) from [from]. Returns the flight time until the last lands.
    @discardableResult
    func launch(amount: Int, from: CGPoint) -> Double {
        guard amount > 0 else { return 0 }
        let n = (amount / 10).coerceIn(4, 12)
        let base = amount / n
        var rest = amount - base * n
        var lastEnd: Float = 0
        for i in 0..<n {
            let a = Float.random(in: 0..<(2 * Float.pi))
            let r = Float.random(in: 50...105)
            let v = base + (rest > 0 ? 1 : 0)
            if rest > 0 { rest -= 1 }
            let start = time + Float(i) * 0.065
            let dur = Float.random(in: 0.78...0.95)
            lastEnd = max(lastEnd, start + dur)
            coins.append(Coin(
                x0: Float(from.x), y0: Float(from.y),
                bx: Float(from.x) + Kt.cos(a) * r, by: Float(from.y) + Kt.sin(a) * r * 0.8,
                start: start, dur: dur, spin: Float.random(in: 7...11), value: v
            ))
        }
        return Double(lastEnd - time)
    }

    func update(_ dt: Float) {
        time += dt
        if coins.isEmpty { return }
        var w = 0
        let n = coins.count
        var arrived = 0
        for i in 0..<n {
            let c = coins[i]
            if time >= c.start + c.dur {
                arrived += c.value
                continue
            }
            coins[w] = c
            w += 1
        }
        if w < n {
            coins.removeLast(n - w)
            onArrive?(arrived, coins.isEmpty)
        }
    }

    func clear() { coins.removeAll(keepingCapacity: true) }

    func draw(_ ctx: GraphicsContext) {
        let tx = Float(target.x)
        let ty = Float(target.y)
        for c in coins {
            let t = ((time - c.start) / c.dur).coerceIn(0, 1)
            if time < c.start { continue }
            // Burst out (ease-out) for the first 30 %, then a curve into the pill (ease-in).
            let x: Float
            let y: Float
            let r: Float
            if t < 0.3 {
                let k = Easing.outCubic(t / 0.3)
                x = c.x0 + (c.bx - c.x0) * k
                y = c.y0 + (c.by - c.y0) * k
                r = 11 + 4 * k
            } else {
                let k = Easing.inQuad((t - 0.3) / 0.7)
                let mx = (c.bx + tx) / 2 + (c.by - ty) * 0.18
                let my = min(c.by, ty) - 40
                let u = 1 - k
                x = u * u * c.bx + 2 * u * k * mx + k * k * tx
                y = u * u * c.by + 2 * u * k * my + k * k * ty
                r = 15 - 5 * k
            }
            ctx.drawCoin(CGFloat(x), CGFloat(y), CGFloat(r), flip: CGFloat(Kt.cos((time - c.start) * c.spin)))
        }
    }
}

/// Full-area canvas of a [CoinShower], redrawn every frame of [loop].
struct CoinShowerLayer: View {
    let shower: CoinShower
    let loop: GameLoop

    var body: some View {
        let frameTick = loop.frame
        let shower = self.shower
        Canvas { ctx, _ in
            _ = frameTick // capture the changing frame so SwiftUI redraws this Canvas every tick
            shower.draw(ctx)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Win dialog: "+N coins" pill that pops in after the score and counts up.
struct WinCoinsRow: View {
    let amount: Int
    let visible: Bool

    @Environment(\.palette) private var p
    @State private var shown: Double = 0
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 6) {
            CoinIcon(size: 30)
            CountingCoinsText(value: shown, color: p.gold, outline: shade(p.gold, 0.45))
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .padding(.vertical, 5)
        .background(Capsule(style: .circular).fill(p.panelAlt))
        .overlay(Capsule(style: .circular).strokeBorder(shade(p.gold, 0.85), lineWidth: 2))
        .scaleEffect(appeared ? 1 : 0.4)
        .opacity(appeared ? 1 : 0)
        .task(id: visible) { await run() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plus \(amount) coins")
    }

    /// After the score count (0.4 s + 1.1 s): pop in, count up, chime.
    private func run() async {
        guard visible else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            shown = 0
            appeared = false
        }
        try? await Task.sleep(for: .milliseconds(1250))
        if Task.isCancelled { return }
        withAnimation(.compose(dampingRatio: 0.5, stiffness: 420)) { appeared = true }
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.7)) { shown = Double(amount) }
        AudioManager.shared.play(.STAR, rate: 1.35, volume: 0.6)
        try? await Task.sleep(for: .milliseconds(700))
        if Task.isCancelled { return }
        AudioManager.shared.play(.CLICK, rate: 1.7, volume: 0.6)
        Haptics.shared.light()
    }
}

private struct CountingCoinsText: View, Animatable {
    var value: Double
    let color: Color
    let outline: Color

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        OutlinedText("+\(GoalTracker.formatNumber(Int(value.rounded()))) coins", fontSize: 22, color: color, outline: outline, outlineWidth: 2, maxLines: 1)
    }
}

/// Tap on the map's coin pill: balance, boosters owned with their prices, and how to earn coins.
struct CoinsInfoDialog: View {
    let visible: Bool
    let extras: ExtrasData
    let onClose: () -> Void

    @Environment(\.palette) private var p

    var body: some View {
        SweetDialog(visible, onDismissRequest: onClose, title: "Coins", ribbonColor: p.gold, showClose: true) {
            HStack(spacing: 8) {
                CoinIcon(size: 44)
                OutlinedText(GoalTracker.formatNumber(extras.coins), fontSize: TypeScale.Title, color: p.gold, outline: shade(p.gold, 0.45), outlineWidth: 2.5)
            }
            Spacer().frame(height: 10)
            VStack(spacing: 8) {
                ForEach(Booster.allCases, id: \.self) { b in
                    HStack(spacing: 10) {
                        BoosterIcon(b, size: 34)
                            .frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 0) {
                            BodyText(b.title, color: p.text, fontSize: TypeScale.Label, textAlign: .leading)
                            BodyText("You have \(extras.count(b))", color: p.subText, fontSize: TypeScale.Caption, textAlign: .leading)
                        }
                        Spacer(minLength: 0)
                        CoinIcon(size: 18)
                        BodyText("\(b.price)", color: p.text, fontSize: TypeScale.Label)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .circular).fill(p.panelAlt))
            Spacer().frame(height: 10)
            BodyText("Win levels for 20 coins + 10 per star, +2 for every move left in Sweet Frenzy. Spin the wheel and collect your daily gift for more!", color: p.subText, fontSize: TypeScale.Label)
            Spacer().frame(height: 14)
            CandyButton3D("OK", onClick: onClose, color: p.success, height: 58, fontSize: 22)
        }
    }
}
