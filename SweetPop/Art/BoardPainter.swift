import SwiftUI
import GameKit

/// Board drawing primitives: outline, checker tiles, jelly and frosting (spec 6.5).
/// The drawing functions are `GraphicsContext` extensions (Kotlin: `DrawScope` extensions inside this object),
/// so call sites read `ctx.drawJelly(cx, cy, cell, layers)`. Units are canvas points.
enum BoardPainter {
    static let Jelly1 = RGBA(argb: 0xFFFF9EDB).with(alpha: 0.78).quantized
    static let Jelly2 = RGBA(argb: 0xFFFF52AD).with(alpha: 0.92).quantized
    static let Cream = Color(argb: 0xFFFFF1D6)
    static let CreamShade = Color(argb: 0xFFE6C996)
    static let PinkCream = Color(argb: 0xFFFFD3E6)
    static let PinkShade = Color(argb: 0xFFE79BC0)
    static let Crack = srgbColor(RGBA(argb: 0xFF8A5A2B).with(alpha: 0.55))
    static let SprinkleColors: [Color] = [
        Color(argb: 0xFFF52945), Color(argb: 0xFF338FFF), Color(argb: 0xFFFFD629), Color(argb: 0xFF38CC52), Color(argb: 0xFFAD4DF5), .white,
    ]

    /// Android raw-pixel constants were tuned at density 2.75 (the reference `Effects.k` uses); in points they
    /// are px / 2.75.
    static let referenceDensity: CGFloat = 2.75

    /// Top-left corner of cell (x, y); y = 0 is the bottom row.
    static func cellLeft(_ originX: CGFloat, _ x: Int, _ cell: CGFloat) -> CGFloat { originX + CGFloat(x) * cell }
    static func cellTop(_ originY: CGFloat, _ y: Int, _ height: Int, _ cell: CGFloat) -> CGFloat { originY + CGFloat(height - 1 - y) * cell }

    @inline(__always)
    fileprivate static func roundRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: max(0, min(r, min(w, h) / 2)), style: .circular)
    }
}

extension GraphicsContext {
    /**
     * Draws the board outline and translucent checker tiles. Tile areas are cleared first so the translucent
     * tiles show the backdrop, not the white outline — done inside its own transparency layer here, so callers
     * don't need an offscreen layer (Android needed `CompositingStrategy.Offscreen`).
     */
    func drawBoardBase(_ board: Board, _ ox: CGFloat, _ oy: CGFloat, _ cell: CGFloat, _ palette: Palette) {
        let grow: CGFloat = 8 / BoardPainter.referenceDensity
        let r = cell * 0.26
        // Android over-draws tiles by half a pixel on each side to hide seams: use one device pixel.
        let px = 1 / max(1, environment.displayScale)
        let tr = cell * 0.12
        drawLayer { layer in
            board.forEachCell { x, y, c in
                guard c.playable else { return }
                let l = BoardPainter.cellLeft(ox, x, cell)
                let t = BoardPainter.cellTop(oy, y, board.height, cell)
                layer.fill(BoardPainter.roundRect(l - grow, t - grow, cell + grow * 2, cell + grow * 2, r + grow), with: .color(palette.boardBorder))
            }
            var clear = layer
            clear.blendMode = .clear
            board.forEachCell { x, y, c in
                guard c.playable else { return }
                let l = BoardPainter.cellLeft(ox, x, cell) - px / 2
                let t = BoardPainter.cellTop(oy, y, board.height, cell) - px / 2
                clear.fill(BoardPainter.roundRect(l, t, cell + px, cell + px, tr), with: .color(.black))
            }
            board.forEachCell { x, y, c in
                guard c.playable else { return }
                let l = BoardPainter.cellLeft(ox, x, cell) - px / 2
                let t = BoardPainter.cellTop(oy, y, board.height, cell) - px / 2
                let col = (x + y) % 2 == 0 ? palette.boardTile : palette.boardTileAlt
                layer.fill(BoardPainter.roundRect(l, t, cell + px, cell + px, tr), with: .color(col))
            }
        }
    }

    /// Jelly square under a candy. [pop] in 0..1 animates a layer popping away (grows and fades).
    func drawJelly(_ cx: CGFloat, _ cy: CGFloat, _ cell: CGFloat, _ layers: Int, pop: CGFloat = -1) {
        if layers <= 0 { return }
        let scale: CGFloat = pop >= 0 ? 1 + 0.35 * pop : 1
        let alpha: Float = pop >= 0 ? Float(1 - pop).coerceIn(0, 1) : 1
        let s = cell * 0.9 * scale
        let col = layers >= 2 ? BoardPainter.Jelly2 : BoardPainter.Jelly1
        let tl = CGPoint(x: cx - s / 2, y: cy - s / 2)
        let body = BoardPainter.roundRect(tl.x, tl.y, s, s, s * 0.24)
        fill(body, with: col.shading(alpha: col.a * alpha))
        stroke(body, with: RGBA.white.shading(alpha: 0.55 * alpha), lineWidth: s * 0.05)
        fill(BoardPainter.roundRect(tl.x + s * 0.12, tl.y + s * 0.1, s * 0.5, s * 0.18, s * 0.09), with: RGBA.white.shading(alpha: 0.38 * alpha))
        let dr = s * 0.05
        fill(Path(ellipseIn: CGRect(x: tl.x + s * 0.76 - dr, y: tl.y + s * 0.2 - dr, width: dr * 2, height: dr * 2)),
             with: RGBA.white.shading(alpha: 0.3 * alpha))
    }

    /// Cream frosting block filling a cell. hp 1 = cream with cracks, hp 2 = pink with sprinkles.
    func drawFrosting(_ cx: CGFloat, _ cy: CGFloat, _ cell: CGFloat, _ hp: Int, _ seed: Int, shake: CGFloat = 0) {
        if hp <= 0 { return }
        let s = cell * 0.96
        let x = cx + shake
        let tl = CGPoint(x: x - s / 2, y: cy - s / 2)
        let r = s * 0.2
        let body = hp >= 2 ? BoardPainter.PinkCream : BoardPainter.Cream
        let shadeCol = hp >= 2 ? BoardPainter.PinkShade : BoardPainter.CreamShade
        fill(BoardPainter.roundRect(tl.x, tl.y, s, s, r), with: .color(shadeCol))
        fill(
            BoardPainter.roundRect(tl.x, tl.y, s, s * 0.86, r),
            with: .linearGradient(Gradient(colors: [.white, body]), startPoint: CGPoint(x: tl.x, y: tl.y), endPoint: CGPoint(x: tl.x, y: tl.y + s * 0.8))
        )
        // Drippy icing edge.
        let dripY = tl.y + s * 0.58
        for i in 0..<4 {
            let dx = tl.x + s * (0.14 + CGFloat(i) * 0.24)
            let len = s * (0.08 + CGFloat((seed * 7 + i * 13) % 5) * 0.025)
            fill(BoardPainter.roundRect(dx, dripY, s * 0.14, len + s * 0.12, s * 0.07), with: .color(body))
        }
        fill(BoardPainter.roundRect(tl.x + s * 0.14, tl.y + s * 0.1, s * 0.42, s * 0.12, s * 0.06), with: RGBA.white.shading(alpha: 0.7))
        if hp >= 2 {
            for i in 0..<7 {
                let h1 = (seed &* 31 &+ i &* 17) & 0xFF
                let h2 = (seed &* 53 &+ i &* 29) & 0xFF
                let px = tl.x + s * (0.18 + 0.64 * (CGFloat(h1) / 255))
                let py = tl.y + s * (0.25 + 0.5 * (CGFloat(h2) / 255))
                let col = BoardPainter.SprinkleColors[Kt.mod(seed + i, BoardPainter.SprinkleColors.count)]
                var c = self
                c.translateBy(x: px, y: py)
                c.rotate(by: .degrees(Double(h1 + h2)))
                var line = Path()
                line.move(to: CGPoint(x: -s * 0.05, y: 0))
                line.addLine(to: CGPoint(x: s * 0.05, y: 0))
                c.stroke(line, with: .color(col), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
            }
        } else {
            let w = s * 0.03
            let a = CGPoint(x: tl.x + s * 0.3, y: tl.y + s * 0.32)
            let b = CGPoint(x: tl.x + s * 0.46, y: tl.y + s * 0.5)
            let c = CGPoint(x: tl.x + s * 0.4, y: tl.y + s * 0.72)
            let d = CGPoint(x: tl.x + s * 0.66, y: tl.y + s * 0.42)
            var cracks = Path()
            cracks.move(to: a); cracks.addLine(to: b)
            cracks.move(to: b); cracks.addLine(to: c)
            cracks.move(to: b); cracks.addLine(to: d)
            cracks.move(to: d); cracks.addLine(to: CGPoint(x: tl.x + s * 0.8, y: tl.y + s * 0.36))
            stroke(cracks, with: .color(BoardPainter.Crack), style: StrokeStyle(lineWidth: w, lineCap: .round))
        }
    }
}
