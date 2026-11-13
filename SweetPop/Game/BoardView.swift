import SwiftUI
import GameKit

/**
 * The whole board: tiles, jelly, candies, frosting and pops, all driven by the view model's game clock.
 * Handles swipe and tap-tap input.
 *
 * iOS: Android drew everything into ONE offscreen Canvas each frame. Here the static outline + checker tiles
 * are a cached Canvas (redrawn only when the board, size or palette change), and everything that moves is a
 * second Canvas redrawn every game frame on top of it — same pixels, far less per-frame work. Candy bitmaps
 * are looked up once per kind into a table instead of hitting the shared cache for every candy.
 */
struct BoardView: View {
    let vm: GameViewModel

    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale
    /// Candy bitmaps are rendered off the main thread; candies are hidden until they are ready.
    @State private var artReadyPx = -1
    @State private var input = BoardInput()
    @State private var art = CandyImageTable()
    /// iOS extras: "Colour-blind symbols" sprites (Extras/UI/ColorBlindSymbols.swift).
    @State private var symbols = ColorBlindSymbolTable()
    @Environment(AppContainer.self) private var container

    init(vm: GameViewModel) {
        self.vm = vm
    }

    var body: some View {
        GeometryReader { geo in
            let w = vm.level.width
            let h = vm.level.height
            let pad: CGFloat = 12
            let cell = max(0, min(min((geo.size.width - pad * 2) / CGFloat(w), (geo.size.height - pad * 2) / CGFloat(h)), 52))
            let bitmapPx = Kt.roundToInt(Double(cell * displayScale))
            let artReady = bitmapPx > 0 && (artReadyPx == bitmapPx || CandyArt.isReady(bitmapPx))
            let colorBlind = Features.colorBlind && container.save.extras.colorBlind
            BoardStage(
                vm: vm, palette: palette, pad: pad, cell: cell, bitmapPx: bitmapPx, artReady: artReady, art: art,
                symbols: colorBlind ? symbols : nil
            )
                .frame(width: cell * CGFloat(w) + pad * 2, height: cell * CGFloat(h) + pad * 2)
                .contentShape(Rectangle())
                .gesture(dragGesture(pad: pad, cell: cell, w: w, h: h))
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(GameScreen.rootSpace))
                } action: { f in
                    vm.boardOrigin = CGPoint(x: f.minX + pad, y: f.minY + pad)
                    vm.cellPx = Float((f.width - pad * 2) / CGFloat(w))
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .task(id: bitmapPx) {
                    guard bitmapPx > 0 else { return }
                    if !CandyArt.isReady(bitmapPx) { await CandyArt.prewarm(bitmapPx) }
                    artReadyPx = bitmapPx
                }
        }
    }

    private func dragGesture(pad: CGFloat, cell: CGFloat, w: Int, h: Int) -> some Gesture {
        let vm = self.vm
        let t = input
        func toCell(_ o: CGPoint) -> Pos? {
            guard cell > 0 else { return nil }
            let cx = Kt.toInt(Float(((o.x - pad) / cell).rounded(.down)))
            let row = Kt.toInt(Float(((o.y - pad) / cell).rounded(.down)))
            let y = h - 1 - row
            if !(0..<w).contains(cx) || !(0..<h).contains(y) { return nil }
            return vm.board[cx, y]?.playable == true ? Pos(cx, y) : nil
        }
        func begin(_ v: DragGesture.Value) {
            t.active = true
            t.down = v.startLocation
            t.start = toCell(v.startLocation)
            t.swiped = false
            vm.onTouch()
        }
        return DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                if !t.active || t.down != v.startLocation { begin(v) }
                t.track(v.location, cell, vm)
            }
            .onEnded { v in
                if !t.active || t.down != v.startLocation { begin(v) }
                // Movement is checked on the release event too, so fast flicks still swap.
                t.track(v.location, cell, vm)
                if !t.swiped, let s = t.start { vm.onTap(s) }
                t.active = false
            }
    }
}

/// Touch state of the board gesture (a reference, so tracking a drag never re-renders the view).
@MainActor
private final class BoardInput {
    var active = false
    var down: CGPoint = .zero
    var start: Pos?
    var swiped = false

    func track(_ p: CGPoint, _ cell: CGFloat, _ vm: GameViewModel) {
        guard !swiped, let s = start else { return }
        let dx = p.x - down.x
        let dy = p.y - down.y
        if max(abs(dx), abs(dy)) > cell * 0.32 {
            swiped = true
            if abs(dx) > abs(dy) {
                vm.onSwipe(s, dx > 0 ? 1 : -1, 0)
            } else {
                vm.onSwipe(s, 0, dy > 0 ? -1 : 1)
            }
        }
    }
}

/// Redrawn every game frame (reads `vm.frame`); the screen shake moves the whole board.
private struct BoardStage: View {
    let vm: GameViewModel
    let palette: Palette
    let pad: CGFloat
    let cell: CGFloat
    let bitmapPx: Int
    let artReady: Bool
    let art: CandyImageTable
    let symbols: ColorBlindSymbolTable?

    var body: some View {
        let frameTick = vm.frame // redraw every game frame
        let shake = vm.effects.shakeOffset()
        let vm = self.vm
        let pad = self.pad
        let cell = self.cell
        let bitmapPx = self.bitmapPx
        let artReady = self.artReady
        let art = self.art
        let symbols = self.symbols
        ZStack(alignment: .topLeading) {
            BoardBase(board: vm.board, pad: pad, cell: cell, palette: palette)
                .equatable()
            Canvas { ctx, _ in
                _ = frameTick // capture the changing frame so SwiftUI redraws this Canvas every tick
                BoardPaint.draw(ctx, vm, pad, cell, bitmapPx, artReady, art, symbols)
            }
        }
        .offset(x: shake.x, y: shake.y)
    }
}

/// Outline + checker tiles (Kotlin `drawBoardBase`); only redrawn when its inputs change.
private struct BoardBase: View, Equatable {
    let board: Board
    let boardID: ObjectIdentifier
    let pad: CGFloat
    let cell: CGFloat
    let palette: Palette

    init(board: Board, pad: CGFloat, cell: CGFloat, palette: Palette) {
        self.board = board
        boardID = ObjectIdentifier(board)
        self.pad = pad
        self.cell = cell
        self.palette = palette
    }

    nonisolated static func == (a: BoardBase, b: BoardBase) -> Bool {
        a.boardID == b.boardID && a.pad == b.pad && a.cell == b.cell && a.palette == b.palette
    }

    var body: some View {
        let board = self.board
        let pad = self.pad
        let cell = self.cell
        let palette = self.palette
        Canvas { ctx, _ in
            ctx.drawBoardBase(board, pad, pad, cell, palette)
        }
    }
}

private let PI_F = Float(Double.pi)
private let SelectRing = RGBA.white.shading(alpha: 0.9)

/// Everything on the board that moves, timed on the game clock (Kotlin `DrawScope.drawBoard`, after the base).
@MainActor
private enum BoardPaint {
    static func draw(
        _ ctx: GraphicsContext, _ vm: GameViewModel, _ pad: CGFloat, _ cell: CGFloat, _ bitmapPx: Int, _ artReady: Bool,
        _ art: CandyImageTable, _ symbols: ColorBlindSymbolTable?
    ) {
        guard cell > 0, let board = vm.board else { return }
        let vis = vm.visuals
        let now = vm.time
        let h = board.height
        @inline(__always) func cx(_ x: Float) -> CGFloat { pad + (CGFloat(x) + 0.5) * cell }
        @inline(__always) func cy(_ y: Float) -> CGFloat { pad + (CGFloat(h - 1) - CGFloat(y) + 0.5) * cell }

        board.forEachCell { x, y, c in
            if c.playable && c.jelly > 0 && c.frosting == 0 { ctx.drawJelly(cx(Float(x)), cy(Float(y)), cell, c.jelly) }
        }
        for j in vis.jellyPops {
            let k = (now - j.start) / 0.35
            if k >= 0 && k <= 1 { ctx.drawJelly(cx(Float(j.x)), cy(Float(j.y)), cell, j.layers, pop: CGFloat(k)) }
        }

        // Hint ping-pong (0..1..0 every 0.45 s each way).
        let hint = vis.hint
        var hintK: Float = 0
        if hint != nil {
            let ph = Kt.rem((now - vis.hintAt) / 0.45, 2)
            let tri = ph < 1 ? ph : 2 - ph
            hintK = tri * tri * (3 - 2 * tri)
        }

        if artReady {
            art.beginFrame(bitmapPx, cell: cell, scale: max(1, ctx.environment.displayScale))
            symbols?.beginFrame(cell: cell, scale: max(1, ctx.environment.displayScale))
            var cc = ctx
            cc.clip(to: Path(CGRect(x: pad, y: pad, width: CGFloat(board.width) * cell, height: CGFloat(h) * cell)))
            board.forEachCell { x, y, c in
                guard let candy = c.candy else { return }
                var fx = Float(x)
                var fy = Float(y)
                var sx: Float = 1
                var sy: Float = 1
                if let m = vis.motions[candy.id] {
                    if now < m.start {
                        fx = m.fromX
                        fy = m.fromY
                    } else if now < m.end {
                        let k = m.ease.apply((now - m.start) / m.dur)
                        fx = m.fromX + (m.toX - m.fromX) * k
                        fy = m.fromY + (m.toY - m.fromY) * k
                    } else if m.squash {
                        let kk = (now - m.end) / 0.22
                        if kk >= 0 && kk <= 1 {
                            let s = Kt.sin(PI_F * kk) * (1 - kk) * 0.22
                            sx = 1 + s
                            sy = 1 - s
                        }
                    }
                }
                var scale: Float = 1
                if let g = vis.grow[candy.id] {
                    let k = ((now - g) / 0.38).coerceIn(0, 1)
                    scale *= Easing.outBack(k, 2.2).coerceAtLeast(0)
                }
                if let p = vis.pulses[candy.id] {
                    let k = ((now - p) / 0.5).coerceIn(0, 1)
                    scale *= 1 + 0.28 * Kt.sin(PI_F * k)
                }
                let pos = Pos(x, y)
                if let hint, hint.first == pos || hint.second == pos { scale *= 1 + 0.14 * hintK }
                let selected = vis.selected == pos
                if selected { scale *= 1.06 + 0.04 * Kt.sin((now - vis.selectedAt) * 9) }
                let px = cx(fx)
                let py = cy(fy) + cell * 0.45 * CGFloat(1 - sy) * CGFloat(scale)
                if selected {
                    let r = CGRect(x: cx(Float(x)) - cell * 0.47, y: cy(Float(y)) - cell * 0.47, width: cell * 0.94, height: cell * 0.94)
                    cc.stroke(Path(roundedRect: r, cornerRadius: cell * 0.24, style: .circular), with: SelectRing, lineWidth: cell * 0.07)
                }
                art.draw(cc, candy.color, candy.special, px, py, cell, CGFloat(sx * scale), CGFloat(sy * scale), 1)
                symbols?.draw(cc, candy.color, px, py, CGFloat(sx * scale), CGFloat(sy * scale), 1)
            }
        }

        board.forEachCell { x, y, c in
            if !c.playable || c.frosting <= 0 { return }
            var shakeX: CGFloat = 0
            if let hit = vis.frostHits[x + y * board.width] {
                let k = ((now - hit) / 0.35).coerceIn(0, 1)
                shakeX = CGFloat(Kt.sin(k * 40)) * cell * 0.07 * CGFloat(1 - k)
            }
            ctx.drawFrosting(cx(Float(x)), cy(Float(y)), cell, c.frosting, x * 7 + y * 13, shake: shakeX)
        }

        if artReady {
            for p in vis.pops {
                let k = ((now - p.start) / 0.3).coerceIn(0, 1)
                let s: Float = k < 0.3 ? 1 + 0.25 * (k / 0.3) : 1.25 * (1 - (k - 0.3) / 0.7)
                art.draw(ctx, p.color, p.special, cx(Float(p.x)), cy(Float(p.y)), cell, CGFloat(s), CGFloat(s), CGFloat(1 - k * 0.6))
                symbols?.draw(ctx, p.color, cx(Float(p.x)), cy(Float(p.y)), CGFloat(s), CGFloat(s), CGFloat(1 - k * 0.6))
            }
        }
    }
}

/**
 * The board's candy bitmaps, resolved once per kind: `CandyArt` images for one bitmap size, plus the
 * frame's resolved images, so drawing a candy is an array lookup. Drawing matches `GraphicsContext.drawCandy`
 * (Kotlin `DrawScope.drawCandy`): bitmap 1.2 × cell, destination snapped to whole device pixels.
 */
@MainActor
private final class CandyImageTable {
    private static let kinds = 7 * 5

    private var px = -1
    private var images = [Image?](repeating: nil, count: CandyImageTable.kinds)
    private var resolved = [GraphicsContext.ResolvedImage?](repeating: nil, count: CandyImageTable.kinds)
    private var resolvedFrame = [Int](repeating: -1, count: CandyImageTable.kinds)
    private var frame = 0
    private var drawn: CGFloat = 0
    private var scale: CGFloat = 1

    func beginFrame(_ bitmapPx: Int, cell: CGFloat, scale: CGFloat) {
        if bitmapPx != px {
            px = bitmapPx
            for i in 0..<Self.kinds {
                images[i] = nil
                resolved[i] = nil
                resolvedFrame[i] = -1
            }
        }
        frame &+= 1
        self.scale = scale
        drawn = CGFloat(CandyPainter.bitmapSize(px)) * (cell / CGFloat(px))
    }

    private func image(_ ctx: GraphicsContext, _ color: CandyColor, _ special: SpecialType) -> GraphicsContext.ResolvedImage? {
        let c: CandyColor = special == .COLOR_BOMB ? .NONE : color
        let k = c.ordinal * 5 + special.ordinal
        if resolvedFrame[k] == frame, let r = resolved[k] { return r }
        var img = images[k]
        if img == nil {
            img = CandyArt.peek(c, special, px)
            images[k] = img
        }
        guard let img else { return nil }
        let r = ctx.resolve(img)
        resolved[k] = r
        resolvedFrame[k] = frame
        return r
    }

    func draw(
        _ ctx: GraphicsContext, _ color: CandyColor, _ special: SpecialType, _ cx: CGFloat, _ cy: CGFloat, _ cell: CGFloat,
        _ scaleX: CGFloat, _ scaleY: CGFloat, _ alpha: CGFloat
    ) {
        if alpha <= 0 || scaleX <= 0 || scaleY <= 0 || cell <= 0 || px <= 0 { return }
        guard let img = image(ctx, color, special) else {
            return
        }
        let w = drawn * scaleX
        let h = drawn * scaleY
        // IntOffset / IntSize in device pixels.
        let x0 = ((cx - w / 2) * scale).rounded() / scale
        let y0 = ((cy - h / 2) * scale).rounded() / scale
        let wd = max(1, (w * scale).rounded()) / scale
        let hd = max(1, (h * scale).rounded()) / scale
        let rect = CGRect(x: x0, y: y0, width: wd, height: hd)
        if alpha < 1 {
            var c = ctx
            c.opacity *= Double(alpha)
            c.draw(img, in: rect)
        } else {
            ctx.draw(img, in: rect)
        }
    }
}
