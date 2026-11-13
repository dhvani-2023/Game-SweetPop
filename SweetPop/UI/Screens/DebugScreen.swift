#if DEBUG
import SwiftUI
import GameKit

/// Debug-only board: play every sound effect and music loop, and preview every candy. Not compiled in Release.
struct DebugScreen: View {
    let onBack: () -> Void

    @Environment(\.palette) private var p
    @Environment(AppContainer.self) private var container
    @Environment(\.safeDrawingInsets) private var safe

    var body: some View {
        let audio = container.audio
        VStack(spacing: 0) {
            ScreenHeader(title: "Debug", onBack: onBack)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    OutlinedText("SOUND EFFECTS", fontSize: TypeScale.Label, outlineWidth: 2)
                    Color.clear.frame(height: 6)
                    FlowRow(spacing: 8, lineSpacing: 8) {
                        ForEach(Sfx.entries, id: \.self) { s in
                            CandyButton3D(s.fileName, onClick: { audio.play(s) }, color: p.accent2, height: 44, fontSize: 15)
                                .fixedSize()
                        }
                        ForEach(SynthBank.CHIME_STEPS.indices, id: \.self) { i in
                            CandyButton3D("chime \(i)", onClick: { audio.playChime(i) }, color: p.sky, height: 44, fontSize: 15)
                                .fixedSize()
                        }
                    }
                    Color.clear.frame(height: 12)
                    OutlinedText("MUSIC", fontSize: TypeScale.Label, outlineWidth: 2)
                    Color.clear.frame(height: 6)
                    FlowRow(spacing: 8, lineSpacing: 0) {
                        CandyButton3D("Menu", onClick: { audio.playMusic(.MENU) }, color: p.accent, height: 48, fontSize: 17).fixedSize()
                        CandyButton3D("Game", onClick: { audio.playMusic(.GAME) }, color: p.accent, height: 48, fontSize: 17).fixedSize()
                        CandyButton3D("Duck", onClick: { audio.duck(true) }, color: p.gold, height: 48, fontSize: 17).fixedSize()
                        CandyButton3D("Unduck", onClick: { audio.duck(false) }, color: p.gold, height: 48, fontSize: 17).fixedSize()
                    }
                    Color.clear.frame(height: 16)
                    OutlinedText("CANDIES", fontSize: TypeScale.Label, outlineWidth: 2)
                    Color.clear.frame(height: 6)
                    CandyCard(color: p.hudBar) {
                        Canvas { ctx, size in
                            let cell = size.width / 5
                            for (i, kind) in CandyArt.allKinds.enumerated() {
                                let col = i % 4
                                let row = i / 4
                                let x = i == 24 ? size.width / 2 : (CGFloat(col) + 0.5) * cell + cell * 0.5
                                let y = (CGFloat(row) + 0.5) * cell * 0.9
                                ctx.drawCandy(kind.0, kind.1, x, y, cell * 0.9)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 380)
                    }
                    Color.clear.frame(height: 12)
                    CandyCard(color: p.hudBar) {
                        Canvas { ctx, _ in
                            let cell: CGFloat = 70
                            ctx.drawJelly(cell * 0.5, cell * 0.55, cell, 1)
                            ctx.drawJelly(cell * 1.6, cell * 0.55, cell, 2)
                            ctx.drawFrosting(cell * 2.7, cell * 0.55, cell, 1, 3)
                            ctx.drawFrosting(cell * 3.8, cell * 0.55, cell, 2, 5)
                        }
                        .frame(width: 300, height: 80)
                    }
                }
                .padding(16)
            }
        }
        .padding(safe)
        .ignoresSafeArea()
    }
}

/// Compose `FlowRow(horizontalArrangement = spacedBy(spacing), verticalArrangement = spacedBy(lineSpacing))`.
private struct FlowRow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(maxWidth: proposal.width ?? .infinity, subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(maxWidth: bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            let needed = row.items.isEmpty ? s.width : row.width + spacing + s.width
            if !row.items.isEmpty && needed > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? s.width : row.width + spacing + s.width
            row.height = max(row.height, s.height)
            row.items.append(i)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
#endif
