import SwiftUI
import Observation
import GameKit

let MAP_ROW: CGFloat = 115
let MAP_BANNER: CGFloat = 76
private let NODE: CGFloat = 64
/// Kotlin `LazyColumn(contentPadding = PaddingValues(top = 150.dp, bottom = 150.dp))`.
let MAP_PADDING: CGFloat = 150

/// Horizontal offset of node [i] in "720-wide" units (spec 11.3).
func mapNodeX(_ i: Int) -> Float {
    Float(270.0 * Foundation.sin(Double(i) * 0.62) * (0.72 + 0.28 * Foundation.sin(Double(i) * 0.17 + 1.3)))
}

private func isEpisodeStart(_ n: Int) -> Bool { (n - 1) % LevelCatalog.LEVELS_PER_EPISODE == 0 }

func mapRowHeight(_ n: Int) -> CGFloat { isEpisodeStart(n) ? MAP_ROW + MAP_BANNER : MAP_ROW }

/// Bottom and top colours of an episode band.
private func bandColors(_ e: Int, _ dark: Bool) -> (RGBA, RGBA) {
    let hue = Float(fmod(0.9 + Double(e) * 0.137, 1.0)) * 360
    return dark
        ? (hsvRGBA(hue, 0.62, 0.36), hsvRGBA(hue + 22, 0.55, 0.42))
        : (hsvRGBA(hue, 0.48, 0.97), hsvRGBA(hue + 22, 0.36, 1))
}

// MARK: - Map state (Kotlin LazyListState + MapNodePositions)

/**
 * Scroll state and geometry of the map. Rows have fixed heights (115 pt, +76 for an episode banner), so every
 * row and node position is exact and analytic: the map is a fixed-height scroll content where only the rows
 * near the viewport exist (a reversed list: level 1 at the bottom, level 2000 at the top).
 *
 * Content coordinates: y = 0 at the top of the scroll content. Map coordinates: the map view's own space
 * (the full screen on Home), i.e. Kotlin's root coordinates used by `MapNodePositions`.
 */
@MainActor
@Observable
final class MapState {
    nonisolated static let count = LevelCatalog.LEVEL_COUNT
    private nonisolated static let perEpisode = LevelCatalog.LEVELS_PER_EPISODE
    nonisolated static let contentHeight: CGFloat =
        MAP_PADDING * 2 + MAP_ROW * CGFloat(count) + MAP_BANNER * CGFloat((count + perEpisode - 1) / perEpisode)
    nonisolated static let anchorID = "map-scroll-anchor"
    nonisolated static let space = "level-map"

    /// Rows that currently exist (viewport ± 2 rows).
    private(set) var visibleRange: ClosedRange<Int> = 1...1
    /// Content y the scroll anchor sits at; `scrollToken` asks the map to scroll there.
    private(set) var anchorY: CGFloat = 0
    private(set) var scrollToken = 0
    private(set) var width: CGFloat = 0
    private(set) var viewportHeight: CGFloat = 0

    /// Map-space y of the content's top edge (−contentOffset), updated every scroll frame without re-rendering.
    @ObservationIgnored private(set) var contentMinY: CGFloat = 0

    /// Content y of the top of level [n]'s row.
    nonisolated static func rowTop(_ n: Int) -> CGFloat {
        let above = count - n
        let bannersAbove = (count - 1) / perEpisode - (n - 1) / perEpisode
        return MAP_PADDING + MAP_ROW * CGFloat(above) + MAP_BANNER * CGFloat(bannersAbove)
    }

    /// The level whose row contains content y (clamped to the list).
    nonisolated static func level(atContentY y: CGFloat) -> Int {
        if y < rowTop(count) { return count }
        var lo = 1, hi = count
        // Smallest n with rowTop(n) <= y (rowTop decreases as n grows).
        while lo < hi {
            let mid = (lo + hi) / 2
            if rowTop(mid) <= y { hi = mid } else { lo = mid + 1 }
        }
        return lo
    }

    /// Horizontal node offset scale: Kotlin `widthPx / 720f * 0.95f`.
    var nodeScale: CGFloat { width / 720 * 0.95 }

    /// Node centre of level [n] in content coordinates (Kotlin: node top at MAP_ROW/2 − NODE/2 − 8 dp, + NODE/2).
    func nodeCenter(_ n: Int) -> CGPoint {
        CGPoint(x: width / 2 + CGFloat(mapNodeX(n)) * nodeScale, y: Self.rowTop(n) + MAP_ROW / 2 - 8)
    }

    /// Node centre of level [n] in map coordinates (Kotlin `positions.centers[n]`).
    func screenCenter(_ n: Int) -> CGPoint {
        let c = nodeCenter(n)
        return CGPoint(x: c.x, y: c.y + contentMinY)
    }

    func layout(width: CGFloat, height: CGFloat) {
        if self.width != width { self.width = width }
        if viewportHeight != height {
            viewportHeight = height
            updateRange()
        }
    }

    func contentScrolled(_ minY: CGFloat) {
        contentMinY = minY
        updateRange()
    }

    /// Kotlin `LazyListState.scrollToItem(index)` on this reversed list: item [index] (level index + 1) is placed
    /// at the start (bottom) content padding, clamped to the scrollable range.
    func scrollToItem(_ index: Int) {
        let level = (index + 1).coerceIn(1, Self.count)
        let rowBottom = Self.rowTop(level) + mapRowHeight(level)
        let maxOffset = max(0, Self.contentHeight - viewportHeight)
        let target = min(max(0, rowBottom + MAP_PADDING - viewportHeight), maxOffset)
        anchorY = target
        contentMinY = -target
        updateRange()
        scrollToken &+= 1
    }

    private func updateRange() {
        guard viewportHeight > 0 else { return }
        let off = -contentMinY
        let topLevel = Self.level(atContentY: off)
        let bottomLevel = Self.level(atContentY: off + viewportHeight)
        let lo = max(1, bottomLevel - 2), hi = min(Self.count, topLevel + 2)
        if lo != visibleRange.lowerBound || hi != visibleRange.upperBound { visibleRange = lo...hi }
    }
}

private struct MapOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - LevelMap

/**
 * The scrolling level map: 2000 rows (level 1 at the bottom), episode bands with ribbons, side decorations
 * and dotted paths. [pin] is drawn above the rows in content coordinates (it scrolls with the nodes).
 * Rows are single canvases (plus the banner every 20 rows) and only the rows near the viewport exist.
 */
struct LevelMap<Pin: View>: View {
    let state: MapState
    let save: SaveData
    let current: Int
    /// Tapped level and its node centre in map coordinates.
    let onNodeTap: (Int, CGPoint) -> Void
    let pin: Pin

    init(state: MapState, save: SaveData, current: Int, onNodeTap: @escaping (Int, CGPoint) -> Void, @ViewBuilder pin: () -> Pin) {
        self.state = state
        self.save = save
        self.current = current
        self.onNodeTap = onNodeTap
        self.pin = pin()
    }

    var body: some View {
        let state = self.state
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    MapContent(state: state, save: save, current: current, onNodeTap: onNodeTap, pin: pin)
                }
                .defaultScrollAnchor(.bottom)
                .modifier(MapScrollPositionModifier(state: state))
                .coordinateSpace(name: MapState.space)
                .onPreferenceChange(MapOffsetKey.self) { y in
                    // iOS 18+ reads the exact offset from onScrollGeometryChange (MapScrollPosition18).
                    if #unavailable(iOS 18) { MainActor.assumeIsolated { state.contentScrolled(y) } }
                }
                .onChange(of: state.scrollToken) {
                    // iOS 18+: MapScrollPositionModifier scrolls to the exact offset. iOS 17: scroll to the anchor
                    // after one layout pass so it sits at its new anchorY.
                    if #unavailable(iOS 18) {
                        DispatchQueue.main.async { proxy.scrollTo(MapState.anchorID, anchor: .top) }
                    }
                }
                .onAppear {
                    state.layout(width: geo.size.width, height: geo.size.height)
                    if #unavailable(iOS 18), state.scrollToken > 0 {
                        DispatchQueue.main.async { proxy.scrollTo(MapState.anchorID, anchor: .top) }
                    }
                }
                .onChange(of: geo.size) { _, size in state.layout(width: size.width, height: size.height) }
            }
        }
        // Edge to edge with no automatic safe-area content insets (Compose LazyColumn: only the 150 dp padding).
        .ignoresSafeArea()
    }
}

private struct MapContent<Pin: View>: View {
    let state: MapState
    let save: SaveData
    let current: Int
    let onNodeTap: (Int, CGPoint) -> Void
    let pin: Pin

    @Environment(\.palette) private var p

    var body: some View {
        let width = state.width
        let range = state.visibleRange
        let anchorY = state.anchorY
        let state = self.state
        let onNodeTap = self.onNodeTap
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: max(1, width), height: MapState.contentHeight)
                .background {
                    GeometryReader { g in
                        Color.clear.preference(key: MapOffsetKey.self, value: g.frame(in: .named(MapState.space)).minY)
                    }
                }
            if width > 0 {
                // Ascending: a higher row draws over the one below it, like the LazyColumn.
                ForEach(Array(range), id: \.self) { n in
                    MapRow(
                        n: n, stars: save.starsFor(n), current: current, width: width,
                        isDark: p.isDark, accent: p.accent,
                        onTap: { onNodeTap(n, state.screenCenter(n)) }
                    )
                    .equatable()
                    .frame(width: width, height: mapRowHeight(n), alignment: .top)
                    .offset(y: MapState.rowTop(n))
                }
                pin
            }
            // Real layout position (padding), so ScrollViewReader.scrollTo finds the anchor where it is drawn.
            Color.clear
                .frame(width: 1, height: 1)
                .id(MapState.anchorID)
                .padding(.top, max(0, anchorY))
        }
        .frame(width: max(1, width), height: MapState.contentHeight, alignment: .topLeading)
    }
}

// MARK: - Row

private struct MapRow: View, Equatable {
    let n: Int
    let stars: Int
    let current: Int
    let width: CGFloat
    let isDark: Bool
    let accent: Color
    let onTap: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    nonisolated static func == (a: MapRow, b: MapRow) -> Bool {
        a.n == b.n && a.stars == b.stars && a.current == b.current && a.width == b.width && a.isDark == b.isDark
            && a.accent == b.accent
    }

    /// Room below the row for side decorations that hang into the row underneath (lollipop sticks).
    private static let overflow: CGFloat = 40

    var body: some View {
        let n = self.n
        let rowH = mapRowHeight(n)
        let first = isEpisodeStart(n)
        let e = LevelCatalog.episodeOf(n)
        let scale = width / 720 * 0.95
        let nodeX = CGFloat(mapNodeX(n)) * scale
        let isCurrent = n == current
        let locked = n > current
        let nodeScale: CGFloat = isCurrent ? 1.15 : 1
        let center = CGPoint(x: width / 2 + nodeX, y: MAP_ROW / 2 - 8)
        let spec = RowSpec(
            n: n, stars: stars, current: current, isDark: isDark, accent: RGBA(accent), scale: scale,
            decor: decorBitmapPx(displayScale), textScale: SweetPopFonts.dynamicScale(dynamicTypeSize)
        )
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                spec.drawBackground(&ctx, CGSize(width: size.width, height: rowH), e: e)
            }
            .frame(width: width, height: rowH + Self.overflow)
            .allowsHitTesting(false)

            if isCurrent {
                NodeGlow(accent: accent)
                    .frame(width: 160, height: 160)
                    .offset(x: center.x - 80, y: center.y - 80)
            }

            Canvas { ctx, _ in
                spec.drawNode(&ctx, center)
            }
            .frame(width: width, height: MAP_ROW)
            .allowsHitTesting(false)

            Color.clear
                .frame(width: NODE * nodeScale, height: NODE * nodeScale)
                .contentShape(Rectangle())
                .onTapGesture { if TapGuard.accept() { onTap() } }
                .offset(x: center.x - NODE * nodeScale / 2, y: center.y - NODE * nodeScale / 2)
                .accessibilityElement()
                .accessibilityLabel(locked ? "Level \(n), locked" : "Level \(n)")
                .accessibilityAddTraits(.isButton)

            if first {
                // Modifier.align(BottomCenter).padding(bottom = 6.dp)
                EpisodeBanner(e: e, isDark: isDark)
                    .padding(.bottom, 6)
                    .frame(width: width, height: rowH, alignment: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: rowH, alignment: .topLeading)
    }
}

/// Everything a row draws, resolved once per row render (no environment reads inside the canvases).
private struct RowSpec {
    let n: Int
    let stars: Int
    let current: Int
    let isDark: Bool
    let accent: RGBA
    let scale: CGFloat
    let decor: Int
    let textScale: CGFloat

    private static let dotShadow = RGBA(0, 0, 0, 0.12)
    private static let textShadow = srgbColor(RGBA(0, 0, 0, 0.3))

    // ------------------------------------------------------------------ background

    func drawBackground(_ ctx: inout GraphicsContext, _ size: CGSize, e: Int) {
        let rowPx = MAP_ROW
        let bannerPx = MAP_BANNER
        let per = LevelCatalog.LEVELS_PER_EPISODE
        let bandH = CGFloat(per) * rowPx + bannerPx
        let k = (n - 1) % per
        let bottomOff: CGFloat = k == 0 ? 0 : bannerPx + CGFloat(k) * rowPx
        let fb = Float(bottomOff / bandH)
        let ft = Float((bottomOff + size.height) / bandH)
        let (cb, ct) = bandColors(e, isDark)
        let top = lerpRGBA(cb, ct, ft).with(alpha: 0.86).quantized
        let bottom = lerpRGBA(cb, ct, fb).with(alpha: 0.86).quantized
        let rect = CGRect(origin: .zero, size: size)
        ctx.fill(
            Path(rect),
            with: .linearGradient(Gradient(colors: [top.color, bottom.color]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
        )

        drawDecoration(&ctx, size)

        // Path dots towards the nodes above and below, clipped to this row.
        let cx = size.width / 2
        let nodeY = rowPx / 2 - 8
        let me = CGPoint(x: cx + CGFloat(mapNodeX(n)) * scale, y: nodeY)
        var dc = ctx
        dc.clip(to: Path(rect))
        if n < LevelCatalog.LEVEL_COUNT {
            let upH = isEpisodeStart(n + 1) ? rowPx + bannerPx : rowPx
            let up = CGPoint(x: cx + CGFloat(mapNodeX(n + 1)) * scale, y: nodeY - upH)
            dots(&dc, me, up, n + 1 > current)
        }
        if n > 1 {
            let down = CGPoint(x: cx + CGFloat(mapNodeX(n - 1)) * scale, y: size.height + nodeY)
            dots(&dc, down, me, n > current)
        }
    }

    private func dots(_ ctx: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ dim: Bool) {
        for t in [CGFloat(0.25), 0.5, 0.75] {
            let c = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            ctx.fill(circle(CGPoint(x: c.x, y: c.y + 2), 7.5), with: Self.dotShadow.shading)
            ctx.fill(circle(c, 6.5), with: RGBA.white.shading(alpha: dim ? 0.45 : 0.95))
        }
    }

    /// Deterministic side decorations: lollipop trees, gumdrop hills, clouds and candies.
    private func drawDecoration(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let r = JavaRandom(Int64(n) &* -0x61c8864680b583eb &+ 0x5DEECE66D)
        if r.nextFloat() > 0.62 { return }
        let W = Float(size.width), H = Float(size.height)
        let nodeOffset = mapNodeX(n) * Float(scale)
        let side: Float = nodeOffset > 0 ? -1 : 1
        let x = W / 2 + side * W * (0.3 + r.nextFloat() * 0.13)
        let y = H * (0.35 + r.nextFloat() * 0.35)
        let cols = CandyColor.PLAYABLE
        let col = RGBA(argb: cols[r.nextInt(cols.count)].argb)
        let alpha: Float = isDark ? 0.75 : 0.92
        switch r.nextInt(4) {
        case 0: // lollipop tree
            let rad = 16 + r.nextFloat() * 8
            let stick = CGRect(x: CGFloat(x - 2.5), y: CGFloat(y), width: 5, height: CGFloat(rad * 2.2))
            ctx.fill(Path(roundedRect: stick, cornerRadius: min(3, 2.5), style: .circular), with: RGBA.white.shading(alpha: alpha))
            let c = CGPoint(x: CGFloat(x), y: CGFloat(y))
            ctx.fill(circle(c, CGFloat(rad + 2)), with: shadeRGBA(col, 0.75).with(alpha: alpha).quantized.shading)
            ctx.fill(circle(c, CGFloat(rad)), with: col.with(alpha: alpha).quantized.shading)
            ctx.stroke(circle(c, CGFloat(rad * 0.62)), with: lightenRGBA(col, 0.5).with(alpha: alpha).quantized.shading, lineWidth: CGFloat(rad * 0.22))
            ctx.fill(circle(CGPoint(x: CGFloat(x - rad * 0.4), y: CGFloat(y - rad * 0.4)), CGFloat(rad * 0.22)), with: RGBA.white.shading(alpha: 0.5 * alpha))
        case 1: // gumdrop hill
            let w = 70 + r.nextFloat() * 40
            let h = w * 0.5
            var path = Path()
            path.move(to: CGPoint(x: CGFloat(x - w / 2), y: CGFloat(H)))
            path.addCurve(
                to: CGPoint(x: CGFloat(x + w / 2), y: CGFloat(H)),
                control1: CGPoint(x: CGFloat(x - w / 2), y: CGFloat(H - h * 1.3)),
                control2: CGPoint(x: CGFloat(x + w / 2), y: CGFloat(H - h * 1.3))
            )
            path.closeSubpath()
            ctx.fill(path, with: lightenRGBA(col, 0.25).with(alpha: alpha * 0.85).quantized.shading)
            for i in 0..<5 {
                let sx = x - w * 0.3 + w * 0.6 * (Float(i) / 4)
                let sy = H - h * (0.35 + 0.25 * Kt.sin(Float(i) * 1.7))
                ctx.fill(circle(CGPoint(x: CGFloat(sx), y: CGFloat(sy)), 2.5), with: RGBA.white.shading(alpha: 0.7 * alpha))
            }
        case 2: // cloud
            let s = CGFloat(14 + r.nextFloat() * 6)
            let c = RGBA.white.with(alpha: 0.55 * alpha).quantized.shading
            let X = CGFloat(x), Y = CGFloat(y)
            ctx.fill(circle(CGPoint(x: X - s, y: Y), s), with: c)
            ctx.fill(circle(CGPoint(x: X, y: Y - s * 0.4), s * 1.3), with: c)
            ctx.fill(circle(CGPoint(x: X + s * 1.1, y: Y), s), with: c)
            ctx.fill(Path(roundedRect: CGRect(x: X - s * 2, y: Y, width: s * 4.1, height: s), cornerRadius: s / 2, style: .circular), with: c)
        default: // scattered candies
            let cs: Float = 34
            let c1 = cols[r.nextInt(cols.count)]
            let rot1 = r.nextFloat() * 60 - 30
            ctx.drawCandy(c1, .NONE, CGFloat(x), CGFloat(y), CGFloat(cs), alpha: CGFloat(alpha), rotationDeg: CGFloat(rot1), bitmapPx: decor)
            let c2 = cols[r.nextInt(cols.count)]
            let rot2 = r.nextFloat() * 60 - 30
            ctx.drawCandy(
                c2, .NONE, CGFloat(x + cs * 0.9 * -side), CGFloat(y + cs * 0.6), CGFloat(cs * 0.75),
                alpha: CGFloat(alpha), rotationDeg: CGFloat(rot2), bitmapPx: decor
            )
        }
    }

    // ------------------------------------------------------------------ node

    /// The node (scaled 1.15 about its centre when current), its number or lock, and the stars under it.
    func drawNode(_ ctx: inout GraphicsContext, _ c: CGPoint) {
        let locked = n > current
        let isCurrent = n == current
        let completed = n < current || stars > 0
        let color: RGBA
        if isCurrent { color = accent }
        else if locked { color = isDark ? Self.nodeLockedDark : Self.nodeLocked }
        else if LevelCatalog.isTricky(n) { color = Self.nodeTricky }
        else { color = Self.nodeDone }

        var nc = ctx
        if isCurrent {
            nc.translateBy(x: c.x, y: c.y)
            nc.scaleBy(x: 1.15, y: 1.15)
            nc.translateBy(x: -c.x, y: -c.y)
        }
        let r = NODE / 2
        nc.fill(circle(CGPoint(x: c.x, y: c.y + r * 0.16), r * 0.92), with: shadeRGBA(color, 0.62).shading)
        nc.fill(circle(c, r * 0.92), with: .color(.white))
        nc.fill(
            circle(c, r * 0.8),
            with: .linearGradient(
                Gradient(colors: [lightenRGBA(color, 0.18).color, color.color]),
                startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)
            )
        )
        nc.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.46, y: c.y - r * 0.72, width: r * 0.92, height: r * 0.42)), with: RGBA.white.shading(alpha: 0.35))

        if locked {
            nc.drawIcon(Icons.Lock, in: CGRect(x: c.x - 13, y: c.y - 13, width: 26, height: 26), tint: .white)
        } else {
            // OutlinedText(n, 21 / 17 sp, outline = shade(color, 0.5), outlineWidth = 2 dp, maxLines = 1).
            let fontSize: CGFloat = n >= 1000 ? 17 : 21
            let tp = TextPaths.layout(String(n), fontSize: fontSize * textScale, maxLines: 1)
            var tc = nc
            tc.translateBy(x: c.x - tp.size.width / 2, y: c.y - tp.size.height / 2)
            var sc = tc
            sc.addFilter(.shadow(color: Self.textShadow, radius: androidBlurSigma(6), x: 0, y: 3))
            sc.stroke(tp.path, with: shadeRGBA(color, 0.5).shading, style: StrokeStyle(lineWidth: 4, lineJoin: .round))
            tc.fill(tp.path, with: .color(.white))
        }

        if completed && !locked {
            // Row(offset y −4, spacedBy −2): StarIcon 17 / 20 (+2 y) / 17 under the 64 pt node box.
            let colLeft = c.x - NODE / 2
            let rowTop = c.y - NODE / 2 + NODE - 4
            ctx.drawStar(colLeft + 7 + 8.5, rowTop + 8.5, 17 * 0.48, stars > 0)
            ctx.drawStar(colLeft + 22 + 10, rowTop + 2 + 10, 20 * 0.48, stars > 1)
            ctx.drawStar(colLeft + 40 + 8.5, rowTop + 8.5, 17 * 0.48, stars > 2)
        }
    }

    private static let nodeDone = RGBA(argb: 0xFFFF73AD)
    private static let nodeTricky = RGBA(argb: 0xFF9B5CFF)
    private static let nodeLocked = RGBA(argb: 0xFFB9A9D6)
    private static let nodeLockedDark = RGBA(argb: 0xFF6D6196)

    @inline(__always)
    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
}

/// Pulsing glow behind the current node: `infiniteRepeatable(tween(1100, EaseInOutSine), Reverse)`, inside the
/// node's 1.15 scale. 160 × 160, centred on the node.
private struct NodeGlow: View {
    let accent: Color

    @Environment(\.routeActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        let mid = RGBA(accent).with(alpha: 0.3).quantized.color
        // Ambient pulse: holds still with Reduce Motion.
        let still = reduceMotion || GameKit.Motion.reduce
        TimelineView(.animation(minimumInterval: nil, paused: !active || still)) { tl in
            let t = still ? 0 : max(0, tl.date.timeIntervalSince(start)) / 1.1
            let phase = t.truncatingRemainder(dividingBy: 2)
            let tri = Float(phase < 1 ? phase : 2 - phase)
            let glow = ComposeCubicBezier.EaseInOutSine.transform(tri)
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = NODE / 2 * 1.15 * CGFloat(1.6 + 0.25 * glow)
                let g = Gradient(colors: [srgbColor(RGBA(1, 1, 1, 0.55 + 0.3 * glow)), mid, RGBA.transparent.color])
                ctx.fill(
                    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(g, center: c, startRadius: 0, endRadius: r)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct EpisodeBanner: View {
    let e: Int
    let isDark: Bool

    var body: some View {
        let (cb, _) = bandColors(e, isDark)
        let hue = Float(fmod(0.9 + Double(e) * 0.137, 1.0)) * 360
        let color = shade(hsvColor(hue, 0.7, 0.95), 0.95)
        RibbonHeader(
            "Episode \(e + 1) · \(LevelCatalog.episodeName(e))",
            isDark ? shade(cb.color, 1.6) : color,
            width: 290, fontSize: 19
        )
    }
}

// MARK: - Pin

extension GraphicsContext {
    /// "You are here" pin with a candy face, centred at [center] (Kotlin `DrawScope.drawMapPin`, points).
    func drawMapPin(_ center: CGPoint, _ t: Float, _ accent: Color) {
        let squash = Kt.sin(t * 4)
        let sx = CGFloat(1 - 0.04 * squash)
        let sy = CGFloat(1 + 0.06 * squash)
        let w: CGFloat = 26
        let h: CGFloat = 34
        var c = self
        c.translateBy(x: center.x, y: center.y)
        // scale(sx, sy, pivot = (0, 0.6h))
        c.translateBy(x: 0, y: h * 0.6)
        c.scaleBy(x: sx, y: sy)
        c.translateBy(x: 0, y: -h * 0.6)

        c.fill(Path(ellipseIn: CGRect(x: -w * 0.45, y: h * 0.55, width: w * 0.9, height: w * 0.3)), with: RGBA.black.shading(alpha: 0.18))
        var pin = Path()
        pin.move(to: CGPoint(x: 0, y: h * 0.62))
        pin.addCurve(to: CGPoint(x: -w * 0.62, y: -h * 0.32), control1: CGPoint(x: -w * 0.2, y: h * 0.2), control2: CGPoint(x: -w * 0.62, y: -h * 0.05))
        pin.addCurve(to: CGPoint(x: w * 0.62, y: -h * 0.32), control1: CGPoint(x: -w * 0.62, y: -h * 0.72), control2: CGPoint(x: w * 0.62, y: -h * 0.72))
        pin.addCurve(to: CGPoint(x: 0, y: h * 0.62), control1: CGPoint(x: w * 0.62, y: -h * 0.05), control2: CGPoint(x: w * 0.2, y: h * 0.2))
        pin.closeSubpath()
        c.stroke(pin, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .butt, lineJoin: .miter, miterLimit: 4))
        c.fill(
            pin,
            with: .linearGradient(
                Gradient(colors: [lighten(accent, 0.25), accent]),
                startPoint: CGPoint(x: 0, y: -h * 0.7), endPoint: CGPoint(x: 0, y: h * 0.6)
            )
        )
        c.fill(Path(ellipseIn: CGRect(x: -w * 0.4, y: -h * 0.62, width: w * 0.5, height: h * 0.2)), with: RGBA.white.shading(alpha: 0.35))
        // Candy face.
        let eyeY = -h * 0.34
        func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }
        c.fill(dot(-w * 0.2, eyeY, w * 0.13), with: .color(.white))
        c.fill(dot(w * 0.2, eyeY, w * 0.13), with: .color(.white))
        c.fill(dot(-w * 0.19, eyeY + w * 0.02, w * 0.07), with: .color(Self.pinInk))
        c.fill(dot(w * 0.21, eyeY + w * 0.02, w * 0.07), with: .color(Self.pinInk))
        var smile = Path()
        smile.move(to: CGPoint(x: -w * 0.16, y: -h * 0.17))
        smile.addQuadCurve(to: CGPoint(x: w * 0.16, y: -h * 0.17), control: CGPoint(x: 0, y: -h * 0.04))
        c.stroke(smile, with: .color(Self.pinInk), style: StrokeStyle(lineWidth: 2.4, lineCap: .butt))
        c.fill(dot(-w * 0.34, -h * 0.2, w * 0.07), with: .color(Self.pinCheek))
        c.fill(dot(w * 0.34, -h * 0.2, w * 0.07), with: .color(Self.pinCheek))
    }

    private static let pinInk = Color(argb: 0xFF2A1240)
    private static let pinCheek = Color(argb: 0xFFFFA3C8)
}

/// Arc position for the pin hop from a to b at progress k (0..1).
func pinHopPosition(_ a: CGPoint, _ b: CGPoint, _ k: Float) -> CGPoint {
    let e = Easing.inOut(k)
    let lift = CGFloat(Kt.sin(Float(Double.pi) * e) * 70)
    let ce = CGFloat(e)
    return CGPoint(x: a.x + (b.x - a.x) * ce, y: a.y + (b.y - a.y) * ce - lift)
}


/// Exact programmatic scrolling (Kotlin `scrollToItem`) with the iOS 18 ScrollPosition API.
private struct MapScrollPositionModifier: ViewModifier {
    let state: MapState

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.modifier(MapScrollPosition18(state: state))
        } else {
            content
        }
    }
}

@available(iOS 18, *)
private struct MapScrollPosition18: ViewModifier {
    let state: MapState
    @State private var position = ScrollPosition(edge: .bottom)

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, y in
                state.contentScrolled(-y)
            }
            .onAppear { if state.scrollToken > 0 { position.scrollTo(y: state.anchorY) } }
            .onChange(of: state.scrollToken) { position.scrollTo(y: state.anchorY) }
    }
}
