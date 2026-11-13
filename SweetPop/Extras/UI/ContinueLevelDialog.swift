import SwiftUI
import GameKit

/// "Continue level N?" on the map after iOS closed the app mid-level: a preview of the saved board, moves and
/// score; Continue restores it exactly, Discard drops it (no life is taken, as when Android's app is closed).
struct ContinueLevelDialog: View {
    let snapshot: LevelSnapshot?
    let onContinue: () -> Void
    let onDiscard: () -> Void

    @Environment(\.palette) private var p
    @State private var last: LevelSnapshot?

    var body: some View {
        ZStack {
            if let s = snapshot ?? last {
                dialog(s)
            }
        }
        .onChange(of: snapshot, initial: true) { _, s in
            if let s { last = s }
        }
    }

    private func dialog(_ s: LevelSnapshot) -> some View {
        SweetDialog(snapshot != nil, onDismissRequest: {}, title: "Welcome Back!", ribbonColor: p.accent2) {
            OutlinedText("Continue level \(s.level)?", fontSize: TypeScale.Headline - 2, color: p.accent, outline: shade(p.accent, 0.5), outlineWidth: 2.5)
            Spacer().frame(height: 10)
            SnapshotPreview(snapshot: s)
                .frame(height: 168)
                .frame(maxWidth: .infinity)
            Spacer().frame(height: 10)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                BodyText("\(s.movesLeft) moves left", color: p.text, fontSize: TypeScale.Label)
                Spacer(minLength: 0)
                BodyText("Score: \(GoalTracker.formatNumber(s.score))", color: p.subText, fontSize: TypeScale.Label)
                Spacer(minLength: 0)
            }
            Spacer().frame(height: 16)
            CandyButton3D("Continue", onClick: onContinue, color: p.success, icon: Icons.Play, breathing: true)
            Spacer().frame(height: 10)
            CandyButton3D("Discard", onClick: onDiscard, color: p.danger, height: 58, fontSize: 22, icon: Icons.Trash)
        }
    }
}

/// Small static render of a saved board: tiles, jelly, candies and frosting.
private struct SnapshotPreview: View {
    let snapshot: LevelSnapshot

    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale
    @Environment(AppContainer.self) private var container

    var body: some View {
        let s = snapshot
        let level = LevelCatalog.get(s.level)
        var id = 0
        let board = s.makeBoard(level) {
            id += 1
            return id
        }
        let palette = self.palette
        let decor = decorBitmapPx(displayScale)
        let colorBlind = Features.colorBlind && container.save.extras.colorBlind
        Canvas { ctx, size in
            let pad: CGFloat = 6
            let cell = min((size.width - pad * 2) / CGFloat(board.width), (size.height - pad * 2) / CGFloat(board.height))
            guard cell > 0 else { return }
            let ox = (size.width - cell * CGFloat(board.width)) / 2
            let oy = (size.height - cell * CGFloat(board.height)) / 2
            ctx.drawBoardBase(board, ox, oy, cell, palette)
            board.forEachCell { x, y, c in
                guard c.playable else { return }
                let cx = BoardPainter.cellLeft(ox, x, cell) + cell / 2
                let cy = BoardPainter.cellTop(oy, y, board.height, cell) + cell / 2
                if c.jelly > 0 && c.frosting == 0 { ctx.drawJelly(cx, cy, cell, c.jelly) }
                if let k = c.candy {
                    ctx.drawCandy(k.color, k.special, cx, cy, cell, bitmapPx: decor)
                    if colorBlind { ctx.drawColorBlindSymbol(k.color, cx, cy, cell) }
                }
                if c.frosting > 0 { ctx.drawFrosting(cx, cy, cell, c.frosting, x * 7 + y * 13) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Saved board of level \(s.level)")
    }
}
