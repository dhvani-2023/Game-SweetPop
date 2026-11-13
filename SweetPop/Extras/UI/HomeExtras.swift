import SwiftUI
import GameKit

/// Map button for the Daily Spin: a round 3D button with a little prize wheel (turning while today's spin is
/// ready) and a red "!" badge.
struct SpinButton: View {
    let available: Bool
    let onClick: () -> Void

    var body: some View {
        let onClick = self.onClick
        VStack(spacing: 0) {
            Button {
                if TapGuard.accept() {
                    AudioManager.shared.play(.CLICK)
                    Haptics.shared.light()
                    onClick()
                }
            } label: {
                EmptyView()
            }
            .buttonStyle(SpinButtonStyle(available: available))
            OutlinedText("Spin", fontSize: TypeScale.Caption, outlineWidth: 2, maxLines: 1)
                .padding(.top, 1)
        }
        .overlay(alignment: .topTrailing) {
            if available {
                AlertBadge()
                    .offset(x: 7, y: -5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.compose(dampingRatio: 0.5, stiffness: 420), value: available)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(available ? "Daily spin, ready" : "Daily spin")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onClick() }
    }
}

private struct SpinButtonStyle: ButtonStyle {
    let available: Bool

    func makeBody(configuration: Configuration) -> some View {
        SpinButtonFace(available: available, pressed: configuration.isPressed)
    }
}

private struct SpinButtonFace: View {
    let available: Bool
    let pressed: Bool

    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size: CGFloat = 56
        let lip: CGFloat = 5
        let color = p.gold
        let still = !available || reduceMotion || Motion.reduce
        ZStack(alignment: .top) {
            Circle()
                .fill(shade(color, 0.6))
                .frame(width: size, height: size)
                .offset(y: lip)
            ZStack {
                Circle().fill(Color.white)
                Circle()
                    .fill(LinearGradient(colors: [lighten(color, 0.2), color], startPoint: .top, endPoint: .bottom))
                    .padding(3)
                ClockView(paused: still) { t in
                    Canvas { ctx, cs in
                        ctx.drawWheelBadge(cs.width / 2, cs.height / 2 + 1, cs.width * 0.34, rotationDeg: still ? 0 : Double(t * 40))
                        // Pointer.
                        var tri = Path()
                        tri.move(to: CGPoint(x: cs.width / 2 - 5, y: cs.height * 0.1))
                        tri.addLine(to: CGPoint(x: cs.width / 2 + 5, y: cs.height * 0.1))
                        tri.addLine(to: CGPoint(x: cs.width / 2, y: cs.height * 0.24))
                        tri.closeSubpath()
                        ctx.fill(tri, with: .color(p.danger))
                        ctx.stroke(tri, with: .color(.white), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    }
                }
            }
            .frame(width: size, height: size)
            .offset(y: pressed ? 4 : 0)
            .animation(pressed ? .timingCurve(0.4, 0, 0.2, 1, duration: 0.06) : .compose(dampingRatio: 0.45, stiffness: 600), value: pressed)
        }
        .frame(width: size, height: size + lip, alignment: .top)
        .contentShape(Rectangle())
    }
}

/// Red "!" badge that pulses (still with Reduce Motion).
struct AlertBadge: View {
    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let badge = ZStack {
            Circle().fill(p.danger)
            Circle().strokeBorder(Color.white, lineWidth: 2)
            OutlinedText("!", fontSize: 16, outline: shade(p.danger, 0.5), outlineWidth: 1.5, shadow: false, maxLines: 1)
                .padding(.bottom, 1)
        }
        .frame(width: 24, height: 24)
        .allowsHitTesting(false)
        if reduceMotion || Motion.reduce {
            badge
        } else {
            badge.phaseAnimator([CGFloat(0.9), CGFloat(1.12)]) { c, s in
                c.scaleEffect(s)
            } animation: { _ in .timingCurve(0.37, 0, 0.63, 1, duration: 0.5) }
        }
    }
}

/// Lays the map's top-bar chips out at a stable scale: the natural width with the widest lives timer ("00:00")
/// decides it, so the row never truncates and never jitters as the timer ticks. 1 when everything fits.
@MainActor
func topBarChipScale(available: CGFloat, stars: Int, coins: Int?, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
    let ds = SweetPopFonts.dynamicScale(dynamicTypeSize)
    func chip(_ text: String) -> CGFloat { 64 + TextPaths.layout(text, fontSize: 18 * ds).size.width }
    var need = chip("00:00") + 8 + chip(String(stars))
    if let coins { need += 8 + chip(GoalTracker.formatNumber(coins)) }
    guard available > 0, need > available else { return 1 }
    return max(0.7, available / need)
}
