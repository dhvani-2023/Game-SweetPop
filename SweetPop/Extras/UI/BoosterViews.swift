import SwiftUI
import GameKit

// In-game booster UI: the bar above the bottom bar, the shop dialog, the Lose dialog's "+5 Moves" button and the
// Lollipop Hammer swing drawn over the board.

@MainActor
func boosterColor(_ b: Booster, _ p: Palette) -> Color {
    switch b {
    case .HAMMER: return p.accent
    case .SWAP: return p.sky
    case .MOVES: return p.success
    }
}

/// Three booster buttons with count badges. An armed Hammer / Free Swap glows until it is used or tapped again.
struct BoosterBar: View {
    let vm: GameViewModel

    @Environment(\.palette) private var p
    @Environment(AppContainer.self) private var container

    var body: some View {
        let vm = self.vm
        let ex = container.save.extras
        let armed = vm.extras.armed
        let live = vm.phase == .PLAYING && vm.dialog == .NONE
        HStack(spacing: 26) {
            ForEach(Booster.allCases, id: \.self) { b in
                BoosterButton(
                    booster: b, count: ex.count(b), armed: armed == b, enabled: live,
                    color: boosterColor(b, p), onTap: { vm.onBoosterTap(b) }
                )
                .opacity(armed == nil || armed == b ? 1 : 0.6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 66)
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.2), value: armed)
    }
}

/// Round 3D booster button (IconButton3D's lip, rim and gloss) with a count badge, or "+" when it must be bought.
struct BoosterButton: View {
    let booster: Booster
    let count: Int
    let armed: Bool
    let enabled: Bool
    let color: Color
    let onTap: () -> Void
    var size: CGFloat = 54

    var body: some View {
        let onTap = self.onTap
        // Outside play (intro, dialogs) taps do nothing; the buttons keep their colours.
        let live = enabled || armed
        Button {
            if live && TapGuard.accept() {
                AudioManager.shared.play(.CLICK)
                Haptics.shared.light()
                onTap()
            }
        } label: {
            EmptyView()
        }
        .buttonStyle(BoosterButtonStyle(booster: booster, count: count, armed: armed, color: color, size: size))
        .accessibilityLabel(booster.title)
        .accessibilityValue(count > 0 ? "\(count) left" : "Buy for \(booster.price) coins")
        .accessibilityAddTraits(armed ? .isSelected : [])
    }
}

private struct BoosterButtonStyle: ButtonStyle {
    let booster: Booster
    let count: Int
    let armed: Bool
    let color: Color
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        BoosterFace(booster: booster, count: count, armed: armed, color: color, size: size, pressed: configuration.isPressed)
    }
}

private struct BoosterFace: View {
    let booster: Booster
    let count: Int
    let armed: Bool
    let color: Color
    let size: CGFloat
    let pressed: Bool

    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let lip: CGFloat = 5
        let depth: CGFloat = 4
        let face = color
        let b = booster
        let s = size
        let decor = decorBitmapPx(displayScale)
        ZStack(alignment: .top) {
            Circle()
                .fill(shade(face, 0.6))
                .frame(width: s, height: s)
                .offset(y: lip)
            ZStack {
                Circle().fill(Color.white)
                ZStack {
                    Circle().fill(LinearGradient(colors: [lighten(face, 0.16), face], startPoint: .top, endPoint: .bottom))
                    Canvas { ctx, cs in
                        let r = CGRect(x: cs.width * 0.2, y: cs.height * 0.08, width: cs.width * 0.6, height: cs.height * 0.3)
                        ctx.fill(Path(ellipseIn: r), with: RGBA.white.shading(alpha: 0.32))
                        ctx.drawBoosterIcon(b, cs.width / 2, cs.height / 2 + cs.height * 0.02, cs.width * 0.7, bitmapPx: decor)
                    }
                }
                .padding(3)
            }
            .frame(width: s, height: s)
            .overlay {
                if armed { ArmedRing(color: p.gold, reduceMotion: reduceMotion || Motion.reduce) }
            }
            .offset(y: pressed ? depth : 0)
            .animation(pressed ? .timingCurve(0.4, 0, 0.2, 1, duration: 0.06) : .compose(dampingRatio: 0.45, stiffness: 600), value: pressed)
        }
        .frame(width: s, height: s + lip, alignment: .top)
        .scaleEffect(armed ? 1.1 : 1)
        .animation(.compose(dampingRatio: 0.5, stiffness: 500), value: armed)
        .overlay(alignment: .topTrailing) {
            CountBadge(count: count, color: count > 0 ? p.danger : p.success)
                .offset(x: 7, y: -5)
        }
        .contentShape(Rectangle())
    }
}

private struct ArmedRing: View {
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            Circle().strokeBorder(color, lineWidth: 4).padding(-6)
        } else {
            Circle().strokeBorder(color, lineWidth: 4).padding(-6)
                .phaseAnimator([0.45, 1.0]) { c, a in
                    c.opacity(a).scaleEffect(0.96 + 0.08 * a)
                } animation: { _ in .timingCurve(0.37, 0, 0.63, 1, duration: 0.55) }
        }
    }
}

/// Small round badge with the booster count, or "+" (buy) at zero.
private struct CountBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        ZStack {
            Circle().fill(color)
            Circle().strokeBorder(Color.white, lineWidth: 2)
            OutlinedText(count > 0 ? String(count) : "+", fontSize: count > 0 ? 13 : 17, outline: shade(color, 0.5), outlineWidth: 1.5, shadow: false, maxLines: 1)
                .padding(.bottom, count > 0 ? 1 : 2)
        }
        .frame(width: 24, height: 24)
        .allowsHitTesting(false)
    }
}

// MARK: - Shop

/// "Buy 1 for N coins" when a booster has run out. Buying uses it right away.
struct BoosterShopDialog: View {
    let visible: Bool
    let booster: Booster?
    let coins: Int
    let onBuy: (Booster) -> Void
    let onClose: () -> Void

    @Environment(\.palette) private var p
    /// Kotlin-style `rememberLast(booster)`: keeps the content while the dialog animates out.
    @State private var last: Booster?

    var body: some View {
        ZStack {
            if let b = booster ?? last {
                dialog(b)
            }
        }
        .onChange(of: booster, initial: true) { _, b in
            if let b { last = b }
        }
    }

    private func dialog(_ b: Booster) -> some View {
        let color = boosterColor(b, p)
        let affordable = coins >= b.price
        return SweetDialog(visible, onDismissRequest: onClose, title: b.title, ribbonColor: color, showClose: true) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [lighten(color, 0.55).opacity(0.9), .clear], center: .center, startRadius: 0, endRadius: 70))
                    .frame(width: 140, height: 140)
                BoosterIcon(b, size: 92)
                    .modifier(Bob())
            }
            .frame(height: 118)
            BodyText(b.blurb, color: p.text)
            Spacer().frame(height: 12)
            HStack(spacing: 6) {
                CoinIcon(size: 30)
                OutlinedText(String(b.price), fontSize: TypeScale.Headline, color: p.gold, outline: shade(p.gold, 0.45), outlineWidth: 2.5)
            }
            BodyText("You have \(GoalTracker.formatNumber(coins)) coins", color: p.subText, fontSize: TypeScale.Label)
            if !affordable {
                Spacer().frame(height: 6)
                BodyText("Not enough coins yet. Win levels and spin the daily wheel to earn more!", color: p.danger, fontSize: TypeScale.Label)
            }
            Spacer().frame(height: 16)
            CandyButton3D("Buy & Use", onClick: { onBuy(b) }, color: p.success, enabled: affordable, breathing: affordable)
            Spacer().frame(height: 10)
            CandyButton3D("Not now", onClick: onClose, color: p.accent2, height: 58, fontSize: 22)
        }
    }
}

/// Gentle up-down bob (still with Reduce Motion).
private struct Bob: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion || Motion.reduce {
            content
        } else {
            content.phaseAnimator([CGFloat(-4), CGFloat(4)]) { c, y in
                c.offset(y: y).rotationEffect(.degrees(Double(y) * 1.2))
            } animation: { _ in .timingCurve(0.37, 0, 0.63, 1, duration: 0.9) }
        }
    }
}

// MARK: - Lose dialog: +5 Moves

/// The Lose dialog's "+5 Moves" (gold, like Android's hidden rewarded button) with a sticker saying what it costs.
struct ExtraMovesButton: View {
    let offer: ExtraMovesOffer

    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 4) {
            CandyButton3D("+5 Moves", onClick: offer.onTake, color: p.gold, height: 58, fontSize: 22, icon: Icons.Play, enabled: offer.affordable)
                .overlay(alignment: .topTrailing) {
                    sticker
                        .rotationEffect(.degrees(8))
                        .offset(x: 6, y: -10)
                        .allowsHitTesting(false)
                }
            if !offer.affordable {
                BodyText("You have \(GoalTracker.formatNumber(offer.coins)) coins", color: p.subText, fontSize: TypeScale.Caption)
            }
        }
    }

    @ViewBuilder
    private var sticker: some View {
        switch offer.kind {
        case .free:
            StickerChip(color: p.accent) {
                OutlinedText(Ads.usesRealAds ? "Watch ad" : "FREE", fontSize: 15, outline: shade(p.accent, 0.5), outlineWidth: 1.5, shadow: false, maxLines: 1)
            }
        case .booster(let n):
            StickerChip(color: p.success) {
                BoosterIcon(.MOVES, size: 18).frame(width: 20, height: 20)
                OutlinedText("×\(n)", fontSize: 15, outline: shade(p.success, 0.5), outlineWidth: 1.5, shadow: false, maxLines: 1)
            }
        case .coins(let price):
            StickerChip(color: p.accent2) {
                CoinIcon(size: 18)
                OutlinedText(String(price), fontSize: 15, outline: shade(p.accent2, 0.5), outlineWidth: 1.5, shadow: false, maxLines: 1)
            }
        }
    }
}

private struct StickerChip<Content: View>: View {
    let color: Color
    let content: Content

    init(color: Color, @ViewBuilder content: () -> Content) {
        self.color = color
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 3) { content }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Capsule(style: .circular).fill(LinearGradient(colors: [lighten(color, 0.12), color], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule(style: .circular).strokeBorder(Color.white, lineWidth: 2))
            .fixedSize()
    }
}

// MARK: - Hammer swing

/// The Lollipop Hammer swinging onto its candy, on the game clock (root coordinates, like the effects layer).
struct HammerSwingLayer: View {
    let vm: GameViewModel

    var body: some View {
        let frameTick = vm.frame
        let vm = self.vm
        Canvas { ctx, _ in
            _ = frameTick // capture the changing frame so SwiftUI redraws this Canvas every tick
            guard let p = vm.extras.hammerAt else { return }
            let t = vm.time - vm.extras.hammerStart
            let total = GameViewModel.HAMMER_IMPACT + 0.32
            guard t >= 0, t <= total else { return }
            let impact = GameViewModel.HAMMER_IMPACT
            // Swing down (ease-in) to the hit, bounce back up and fade.
            let rot: Double
            let alpha: Double
            if t < impact {
                let k = Double(Easing.inQuad(t / impact))
                rot = -75 + 80 * k
                alpha = min(1, Double(t) / 0.05)
            } else {
                let k = Double((t - impact) / 0.32)
                rot = 5 - 30 * Double(Easing.outCubic(Float(k)))
                alpha = 1 - k
            }
            let cell = CGFloat(vm.cellPx)
            let c = vm.center(p)
            var g = ctx
            g.translateBy(x: -vm.screenOrigin.x, y: -vm.screenOrigin.y)
            g.opacity = alpha
            // Pivot near the end of the stick, below-left of the candy; the head lands on the cell.
            let pivot = CGPoint(x: CGFloat(c.x) - cell * 0.95, y: CGFloat(c.y) + cell * 1.1)
            g.translateBy(x: pivot.x, y: pivot.y)
            g.rotate(by: .degrees(rot))
            g.translateBy(x: -pivot.x, y: -pivot.y)
            g.drawLollipopHammer(CGFloat(c.x) - cell * 0.15, CGFloat(c.y) + cell * 0.25, cell * 1.9)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
