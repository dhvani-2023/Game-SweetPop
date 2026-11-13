import SwiftUI
import GameKit

/**
 * 7-day login gift, shown on the first map visit of a new day: 20 / 30 / 40 / 60 / 80 / 100 / 200 coins, day 7
 * also one of each booster. Earlier days of the streak are ticked, today's tile glows. Claiming is the only way
 * out (the gift is saved on "Claim").
 */
struct LoginGiftDialog: View {
    /// Today's gift day (1…7), nil = hidden.
    let day: Int?
    let onClaim: (Int) -> Void

    @Environment(\.palette) private var p
    @State private var last = 1

    var body: some View {
        let d = day ?? last
        SweetDialog(day != nil, onDismissRequest: {}, title: "Daily Gift", ribbonColor: p.accent) {
            BodyText(d == 1 ? "Come back every day for bigger gifts!" : "Day \(d) in a row — sweet!", color: p.text)
            Spacer().frame(height: 12)
            Grid(horizontalSpacing: 7, verticalSpacing: 7) {
                GridRow {
                    ForEach(1...4, id: \.self) { i in GiftTile(day: i, today: d) }
                }
                GridRow {
                    GiftTile(day: 5, today: d)
                    GiftTile(day: 6, today: d)
                    GiftTile(day: 7, today: d)
                        .gridCellColumns(2)
                }
            }
            Spacer().frame(height: 16)
            CandyButton3D("Claim", onClick: { onClaim(d) }, color: p.success, icon: Icons.Check, breathing: true)
        }
        .onChange(of: day, initial: true) { _, v in
            if let v { last = v }
        }
    }
}

private struct GiftTile: View {
    let day: Int
    let today: Int

    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let claimed = day < today
        let isToday = day == today
        let shape = RoundedRectangle(cornerRadius: 14, style: .circular)
        VStack(spacing: 2) {
            BodyText("Day \(day)", color: isToday ? .white : p.subText, fontSize: TypeScale.Caption)
            if day == LoginGift.DAYS {
                HStack(spacing: 2) {
                    GiftBoxIcon(size: 34)
                    VStack(spacing: 0) {
                        coins
                        HStack(spacing: 0) {
                            ForEach(Booster.allCases, id: \.self) { b in
                                BoosterIcon(b, size: 15).frame(width: 17, height: 17)
                            }
                        }
                    }
                }
            } else {
                CoinIcon(size: 26)
                coins
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background(shape.fill(isToday
            ? LinearGradient(colors: [lighten(p.accent, 0.1), p.accent2], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [p.panelAlt, p.panelAlt], startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(isToday ? p.gold : p.cardBorder, lineWidth: isToday ? 3 : 2))
        .overlay {
            if claimed {
                ZStack {
                    shape.fill(srgbColor(RGBA(1, 1, 1, 0.55)))
                    ZStack {
                        Circle().fill(p.success)
                        Circle().strokeBorder(Color.white, lineWidth: 2)
                        Icon(Icons.Check, contentDescription: nil, tint: .white).frame(width: 18, height: 18)
                    }
                    .frame(width: 28, height: 28)
                }
            }
        }
        .modifier(TodayPulse(on: isToday && !(reduceMotion || Motion.reduce)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day \(day): \(LoginGift.coins(day: day)) coins\(day == LoginGift.DAYS ? " and one of each booster" : "")\(claimed ? ", claimed" : isToday ? ", today" : "")")
    }

    private var coins: some View {
        OutlinedText(String(LoginGift.coins(day: day)), fontSize: 16, color: day == today ? .white : p.gold,
                     outline: day == today ? shade(p.accent2, 0.5) : shade(p.gold, 0.45), outlineWidth: 1.5, shadow: false, maxLines: 1)
    }
}

private struct TodayPulse: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            content.phaseAnimator([CGFloat(1), CGFloat(1.06)]) { c, s in
                c.scaleEffect(s)
            } animation: { _ in .timingCurve(0.37, 0, 0.63, 1, duration: 0.6) }
        } else {
            content
        }
    }
}

private struct GiftBoxIcon: View {
    let size: CGFloat

    var body: some View {
        let s = size
        Canvas { ctx, cs in ctx.drawGiftBox(cs.width / 2, cs.height / 2 + s * 0.06, s * 0.9) }
            .frame(width: s, height: s)
            .allowsHitTesting(false)
    }
}
