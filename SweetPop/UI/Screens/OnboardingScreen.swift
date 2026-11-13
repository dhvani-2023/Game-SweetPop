import SwiftUI
import GameKit

/// Android raw-pixel constants (canvas offsets / stroke widths in px) were tuned at density 2.75.
private let refDensity: CGFloat = BoardPainter.referenceDensity

private struct PageSpec {
    let title: String
    let body: String
    let glow: Color
}

private let PAGES: [PageSpec] = [
    PageSpec(title: "Swap & Match", body: "Swipe a candy to swap it with its neighbour. Line up 3 or more of the same colour to pop them!", glow: Color(argb: 0xFFFF7EC4)),
    PageSpec(title: "Make Sweet Specials", body: "Match 4 for a Line Blast, an L or T shape for a Big Pop, and 5 in a row for a Colour Bomb!", glow: Color(argb: 0xFFC59BFF)),
    PageSpec(title: "2000 Levels to Pop", body: "Clear jelly, break frosting and collect candies. Play anywhere — no internet needed.", glow: Color(argb: 0xFF6FD3FF)),
]

/// Kotlin `TextStyle(lineHeight = …)` for Fredoka: SwiftUI line spacing that gives the same baseline-to-baseline step.
func fredokaLineSpacing(fontSize: CGFloat, lineHeight: CGFloat, dynamicType: DynamicTypeSize) -> CGFloat {
    let f = SweetPopFonts.ctFont(fontSize)
    let natural = CTFontGetAscent(f) + CTFontGetDescent(f)
    return max(0, lineHeight - natural) * SweetPopFonts.dynamicScale(dynamicType)
}

/// Three swipeable pages (swap demo, specials, mini map) with a Skip chip, page dots and Next / Let's Play!.
struct OnboardingScreen: View {
    let onFinish: () -> Void
    let onOpenDoc: (String) -> Void

    @Environment(\.palette) private var p
    @Environment(\.safeDrawingInsets) private var safe

    /// HorizontalPager current page (the page nearest the centre, like Compose's `currentPage`).
    @State private var page: Int? = 0

    var body: some View {
        let current = page ?? 0
        let last = current == PAGES.count - 1
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                GlassChip("Skip", onClick: onFinish)
            }
            .padding(.horizontal, 16)
            .frame(height: 60)

            // HorizontalPager(weight(1f).fillMaxWidth()).
            GeometryReader { g in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(PAGES.indices, id: \.self) { i in
                            OnboardingPage(page: i, onOpenDoc: onOpenDoc)
                                .frame(width: g.size.width, height: g.size.height)
                                .id(i)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page, anchor: .center)
                .scrollClipDisabled() // the pager is full width; pages may overflow vertically like in Compose
            }

            HStack(spacing: 10) {
                ForEach(PAGES.indices, id: \.self) { i in
                    let active = current == i
                    Capsule(style: .circular)
                        .fill(active ? Color.white : srgbColor(RGBA(1, 1, 1, 0.4)))
                        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.2), value: active)
                        .frame(width: active ? 76 : 26, height: 26)
                        .animation(.compose(dampingRatio: 0.6, stiffness: 500), value: active)
                }
            }
            .padding(.vertical, 14)

            CandyButton3D(
                last ? "Let's Play!" : "Next",
                onClick: {
                    if last {
                        onFinish()
                    } else {
                        // pager.animateScrollToPage(currentPage + 1): spring(stiffness = StiffnessMediumLow).
                        withAnimation(.compose(dampingRatio: 1, stiffness: 400)) { page = current + 1 }
                    }
                },
                color: p.success,
                breathing: last
            )
            .frame(width: 270)
            .padding(.bottom, 18)
        }
        .padding(safe)
        .ignoresSafeArea()
    }
}

private struct OnboardingPage: View {
    let page: Int
    let onOpenDoc: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let spec = PAGES[page]
        VStack(spacing: 0) {
            ArtCard(glow: spec.glow) {
                switch page {
                case 0: SwapDemo()
                case 1: SpecialsShowcase()
                default: MiniMap()
                }
            }
            Color.clear.frame(height: 22)
            OutlinedText(spec.title, fontSize: TypeScale.Title, brush: TitleGradient)
            Color.clear.frame(height: 10)
            Text(spec.body)
                .font(.fredoka(TypeScale.Body))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .lineSpacing(fredokaLineSpacing(fontSize: TypeScale.Body, lineHeight: 25, dynamicType: dynamicTypeSize))
            if page == PAGES.count - 1 {
                Color.clear.frame(height: 16)
                LegalLinks(onOpenDoc: onOpenDoc)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "By playing you agree to our Terms & Conditions and Privacy Policy" with gold underlined links.
private struct LegalLinks: View {
    let onOpenDoc: (String) -> Void

    @Environment(\.palette) private var p

    var body: some View {
        var text = AttributedString("By playing you agree to our ")
        text.append(link("Terms & Conditions", "terms"))
        text.append(AttributedString(" and "))
        text.append(link("Privacy Policy", "privacy"))
        let onOpenDoc = self.onOpenDoc
        return Text(text)
            .font(.fredoka(TypeScale.Label))
            .foregroundStyle(srgbColor(RGBA(1, 1, 1, 0.9)))
            .multilineTextAlignment(.center)
            .tint(p.gold)
            .environment(\.openURL, OpenURLAction { url in
                onOpenDoc(url.host ?? "terms")
                return .handled
            })
    }

    private func link(_ label: String, _ kind: String) -> AttributedString {
        var s = AttributedString(label)
        s.link = URL(string: "sweetpop-doc://\(kind)")
        s.foregroundColor = p.gold
        s.underlineStyle = .single
        return s
    }
}

/// Art card rays: 12 wedges around the origin (unit radius), w = 0.12 rad either side.
private let artCardRays: Path = {
    var path = Path()
    for i in 0..<12 {
        let a = Float(Double(i) * 2 * Double.pi / 12)
        let w: Float = 0.12
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: CGFloat(Kt.cos(a - w)), y: CGFloat(Kt.sin(a - w))))
        path.addLine(to: CGPoint(x: CGFloat(Kt.cos(a + w)), y: CGFloat(Kt.sin(a + w))))
        path.closeSubpath()
    }
    return path
}()

/// Frosted glass card with a coloured glow and slowly turning rays behind it.
private struct ArtCard<Content: View>: View {
    let glow: Color
    let content: Content

    @Environment(\.routeActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    init(glow: Color, @ViewBuilder content: () -> Content) {
        self.glow = glow
        self.content = content()
    }

    var body: some View {
        let glowRGBA = RGBA(glow)
        let glowGradient = Gradient(colors: [
            srgbColor(glowRGBA.with(alpha: 0.75)), srgbColor(glowRGBA.with(alpha: 0.2)), RGBA.transparent.color,
        ])
        let rayGradient = Gradient(colors: [srgbColor(RGBA(1, 1, 1, 0.22)), RGBA.transparent.color])
        let shape = RoundedRectangle(cornerRadius: 32, style: .circular)
        // Decorative rays hold still with Reduce Motion.
        let still = reduceMotion || GameKit.Motion.reduce
        ZStack {
            // Compose `Canvas(Modifier.size(420.dp))` is clamped to the 310 × 270 box.
            TimelineView(.animation(minimumInterval: nil, paused: !active || still)) { tl in
                let t = still ? 0 : Float(max(0, tl.date.timeIntervalSince(start)))
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let r = min(size.width, size.height) / 2
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                        with: .radialGradient(glowGradient, center: c, startRadius: 0, endRadius: r)
                    )
                    var rc = ctx
                    rc.translateBy(x: c.x, y: c.y)
                    rc.rotate(by: .degrees(Double(t * 10)))
                    rc.scaleBy(x: r, y: r)
                    rc.fill(artCardRays, with: .radialGradient(rayGradient, center: .zero, startRadius: 0, endRadius: 1))
                }
            }
            .allowsHitTesting(false)

            ZStack { content }
                .frame(width: 290, height: 250)
                .background(shape.fill(LinearGradient(
                    colors: [srgbColor(RGBA(1, 1, 1, 0.32)), srgbColor(RGBA(1, 1, 1, 0.14))],
                    startPoint: .top, endPoint: .bottom
                )))
                .clipShape(shape)
                .overlay(shape.strokeBorder(srgbColor(RGBA(1, 1, 1, 0.5)), lineWidth: 2))
        }
        .frame(width: 310, height: 270)
    }
}

/// Canvas drawn with `margin` extra room on every side (Compose canvases draw outside their bounds; the art card
/// clips), keeping the layout size of the Kotlin canvas.
private struct OverflowCanvas: View {
    let width: CGFloat
    let height: CGFloat
    var margin: CGFloat = 40
    let renderer: (inout GraphicsContext, CGSize) -> Void

    var body: some View {
        let m = margin
        let w = width, h = height
        let renderer = self.renderer
        Color.clear
            .frame(width: w, height: h)
            .overlay {
                Canvas { ctx, _ in
                    ctx.translateBy(x: m, y: m)
                    renderer(&ctx, CGSize(width: w, height: h))
                }
                .frame(width: w + m * 2, height: h + m * 2)
                .allowsHitTesting(false)
            }
    }
}

/// Looping 3×3 demo: a finger swipes the bottom-right red left and three reds pop.
private struct SwapDemo: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.routeActive) private var active
    @Environment(AppContainer.self) private var container
    @State private var start = Date()

    private static let grid: [[CandyColor]] = [
        [.BLUE, .RED, .PURPLE],
        [.GREEN, .RED, .YELLOW],
        [.YELLOW, .ORANGE, .RED],
    ]

    private static let tiles = RGBA(argb: 0xFF26306E).with(alpha: 0.55).quantized
    private static let tilesAlt = tiles.with(alpha: 0.4).quantized
    private static let fingerRing = RGBA(argb: 0xFF4A1C6E).with(alpha: 0.3).quantized

    var body: some View {
        let decor = decorBitmapPx(displayScale)
        // iOS extras: the demo candies carry the colour-blind symbols when that setting is on.
        let colorBlind = Features.colorBlind && container.save.extras.colorBlind
        TimelineView(.animation(minimumInterval: nil, paused: !active)) { tl in
            let clock = Float(max(0, tl.date.timeIntervalSince(start)))
            OverflowCanvas(width: 210, height: 210) { ctx, size in
                Self.draw(&ctx, size, clock, decor, colorBlind)
            }
        }
    }

    private static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ clock: Float, _ decor: Int, _ colorBlind: Bool) {
        let t = fmodf(clock, 4.2)
        let cell = Float(size.width) / 3
        func center(_ col: Float, _ row: Float) -> CGPoint {
            CGPoint(x: CGFloat((col + 0.5) * cell), y: CGFloat((row + 0.5) * cell))
        }
        let fadeIn: Float = t > 3.6 ? 1 - (t - 3.6) / 0.6 : 1
        let appear = (t / 0.3).coerceIn(0, 1)
        let px1 = 2 / refDensity, px2 = 4 / refDensity
        let cl = CGFloat(cell)
        for r in 0..<3 {
            for c in 0..<3 {
                let rect = CGRect(x: CGFloat(c) * cl + px1, y: CGFloat(r) * cl + px1, width: cl - px2, height: cl - px2)
                ctx.fill(
                    Path(roundedRect: rect, cornerRadius: min(cl * 0.18, rect.width / 2), style: .circular),
                    with: ((r + c) % 2 == 0 ? tiles : tilesAlt).shading
                )
            }
        }
        let swapK = Easing.inOut(((t - 0.9) / 0.35).coerceIn(0, 1))
        let popK = ((t - 1.45) / 0.4).coerceIn(0, 1)
        for r in 0..<3 {
            for c in 0..<3 {
                var col = Float(c)
                let color = grid[r][c]
                if r == 2 && c == 2 { col = 2 - swapK }
                if r == 2 && c == 1 { col = 1 + swapK }
                let isMatched = (c == 1 && r < 2) || (r == 2 && c == 2)
                var s: Float = 1
                var a = appear * fadeIn
                if isMatched && popK > 0 {
                    s = popK < 0.3 ? 1 + popK : 1.3 * (1 - (popK - 0.3) / 0.7)
                    a *= 1 - popK * 0.5
                }
                if isMatched && t > 1.85 { continue }
                let ctr = center(col, Float(r))
                ctx.drawCandy(color, .NONE, ctr.x, ctr.y, cl * 0.95, scaleX: CGFloat(s), scaleY: CGFloat(s), alpha: CGFloat(a), bitmapPx: decor)
                if colorBlind { ctx.drawColorBlindSymbol(color, ctr.x, ctr.y, cl * 0.95, scale: CGFloat(s), alpha: CGFloat(a)) }
            }
        }
        if t >= 1.45 && t <= 2.2 {
            let k = (t - 1.45) / 0.75
            for r in 0..<3 {
                let base = center(1, Float(r))
                let p = CGPoint(
                    x: base.x + CGFloat(cell * 0.3 * Kt.cos(Float(r) * 2 + k * 6)),
                    y: base.y + CGFloat(-cell * 0.4 * k)
                )
                sparkleStar(&ctx, p, CGFloat(cell * 0.18 * (1 - k)))
            }
        }
        // Finger dot.
        let fingerStart = CGPoint(x: size.width * 1.05, y: size.height * 1.1)
        let onCandy = center(2, 2)
        let target = center(1, 2)
        func mix(_ a: CGPoint, _ b: CGPoint, _ k: Float) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * CGFloat(k), y: a.y + (b.y - a.y) * CGFloat(k))
        }
        let fingerPos: CGPoint?
        if t < 0.2 { fingerPos = nil }
        else if t < 0.85 { fingerPos = mix(fingerStart, onCandy, Easing.outCubic((t - 0.2) / 0.65)) }
        else if t < 1.25 { fingerPos = mix(onCandy, target, swapK) }
        else if t < 1.6 { fingerPos = target }
        else { fingerPos = nil }
        if let f = fingerPos {
            func circle(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: f.x - r, y: f.y - r, width: r * 2, height: r * 2)) }
            ctx.fill(circle(cl * 0.32), with: RGBA.white.shading(alpha: 0.35))
            ctx.fill(circle(cl * 0.2), with: RGBA.white.shading(alpha: 0.9))
            ctx.stroke(circle(cl * 0.2), with: fingerRing.shading, lineWidth: 3 / refDensity)
        }
    }

    private static func sparkleStar(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        if r <= 0 { return }
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + r * 0.12, y: c.y - r * 0.12))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + r * 0.12, y: c.y + r * 0.12))
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - r * 0.12, y: c.y + r * 0.12))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - r * 0.12, y: c.y - r * 0.12))
        path.closeSubpath()
        ctx.fill(path, with: .color(.white))
    }
}

/**
 * Canvas text the way Android renders it here: `drawText(…, drawStyle = Stroke(5f))` followed by a plain
 * `drawText(…)` keeps the stroke style on the reused text paint (Compose ignores a null draw style), so both
 * passes are 5 px strokes and the label shows as white outlined glyphs (see Reference/Android 04 and 05).
 */
private func drawAndroidStrokedLabel(_ ctx: inout GraphicsContext, _ tp: TextPath, _ topLeft: CGPoint, _ under: Color) {
    var c = ctx
    c.translateBy(x: topLeft.x, y: topLeft.y)
    let style = StrokeStyle(lineWidth: 5 / refDensity, lineCap: .butt, lineJoin: .miter, miterLimit: 4)
    c.stroke(tp.path, with: .color(under), style: style)
    c.stroke(tp.path, with: .color(.white), style: style)
}

/// Striped, wrapped and colour-bomb candies bobbing with their names.
private struct SpecialsShowcase: View {
    @Environment(\.palette) private var p
    @Environment(\.displayScale) private var displayScale
    @Environment(\.routeActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private static let items: [(CandyColor, SpecialType, String)] = [
        (.RED, .STRIPED_H, "Line Blast"),
        (.GREEN, .WRAPPED, "Big Pop"),
        (.NONE, .COLOR_BOMB, "Colour Bomb"),
    ]
    private static let plum = Color(argb: 0xFF4A1C6E)

    var body: some View {
        let decor = decorBitmapPx(displayScale)
        // The bobbing is decorative: still with Reduce Motion.
        let still = reduceMotion || GameKit.Motion.reduce
        VStack(spacing: 0) {
            TimelineView(.animation(minimumInterval: nil, paused: !active || still)) { tl in
                let t = still ? 0 : Float(max(0, tl.date.timeIntervalSince(start)))
                OverflowCanvas(width: 270, height: 150) { ctx, size in
                    let cell = Float(size.width) / 3.4
                    for (i, item) in Self.items.enumerated() {
                        let (c, s, label) = item
                        let cx = Float(size.width) * (Float(i) + 0.5) / 3
                        let bob = Kt.sin(t * 2.4 + Float(i) * 1.3) * 8
                        ctx.drawCandy(
                            c, s, CGFloat(cx), CGFloat(Float(size.height) * 0.38 + bob), CGFloat(cell),
                            rotationDeg: CGFloat(Kt.sin(t * 1.5 + Float(i)) * 8), bitmapPx: decor
                        )
                        let tp = TextPaths.layout(label, fontSize: 15)
                        let tl = CGPoint(x: CGFloat(cx) - tp.size.width / 2, y: size.height * 0.8)
                        drawAndroidStrokedLabel(&ctx, tp, tl, Self.plum)
                    }
                }
            }
            OutlinedText(
                "Swap two specials together for huge combos!", fontSize: 15, color: p.gold,
                outline: shade(p.gold, 0.45), outlineWidth: 2
            )
            .padding(.horizontal, 14)
        }
    }
}

/// Four map nodes along a winding path with the "you are here" pin.
private struct MiniMap: View {
    @Environment(\.palette) private var p
    @Environment(\.routeActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        let accent = p.accent
        // Only the pin bobs here (decorative): still with Reduce Motion.
        let still = reduceMotion || GameKit.Motion.reduce
        TimelineView(.animation(minimumInterval: nil, paused: !active || still)) { tl in
            let t = still ? 0 : Float(max(0, tl.date.timeIntervalSince(start)))
            OverflowCanvas(width: 260, height: 220) { ctx, size in
                Self.draw(&ctx, size, t, accent)
            }
        }
    }

    private static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Float, _ accent: Color) {
        let w = size.width, h = size.height
        let pts = [
            CGPoint(x: w * 0.2, y: h * 0.86),
            CGPoint(x: w * 0.62, y: h * 0.7),
            CGPoint(x: w * 0.32, y: h * 0.46),
            CGPoint(x: w * 0.74, y: h * 0.24),
        ]
        for i in 0..<3 {
            for k in 1...3 {
                let f = CGFloat(k) / 4
                let c = CGPoint(x: pts[i].x + (pts[i + 1].x - pts[i].x) * f, y: pts[i].y + (pts[i + 1].y - pts[i].y) * f)
                ctx.fill(circle(c, 4.5), with: RGBA.white.shading(alpha: i == 2 ? 0.45 : 0.95))
            }
        }
        let r: CGFloat = 24
        let stars = [3, 2, 3]
        for (i, c) in pts.enumerated() {
            let locked = i == 3
            let color: Color = locked ? CandyColors.nodeLocked : (i == 2 ? accent : CandyColors.nodeDone)
            ctx.fill(circle(CGPoint(x: c.x, y: c.y + r * 0.16), r), with: .color(shade(color, 0.62)))
            ctx.fill(circle(c, r), with: .color(.white))
            ctx.fill(
                circle(c, r * 0.86),
                with: .linearGradient(
                    Gradient(colors: [lighten(color, 0.18), color]),
                    startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)
                )
            )
            if !locked {
                let tp = TextPaths.layout(String(i + 1), fontSize: 18)
                let tl = CGPoint(x: c.x - tp.size.width / 2, y: c.y - tp.size.height / 2)
                drawAndroidStrokedLabel(&ctx, tp, tl, shade(color, 0.5))
                for s in 0..<3 {
                    ctx.drawStar(
                        c.x + CGFloat(s - 1) * r * 0.62, c.y + r * 1.2 + (s == 1 ? r * 0.1 : 0), r * 0.3, s < stars[i]
                    )
                }
            } else {
                drawLock(&ctx, c, r * 0.5)
            }
        }
        let pin = CGPoint(x: pts[2].x, y: pts[2].y - r - 26 + CGFloat(Kt.sin(t * 2.2) * 4))
        ctx.drawMapPin(pin, t, accent)
    }

    private static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    private static func drawLock(_ ctx: inout GraphicsContext, _ c: CGPoint, _ s: CGFloat) {
        let body = CGRect(x: c.x - s * 0.7, y: c.y - s * 0.15, width: s * 1.4, height: s * 1.05)
        ctx.fill(Path(roundedRect: body, cornerRadius: s * 0.2, style: .circular), with: .color(.white))
        // drawArc(startAngle 180°, sweep 180°) over the oval (c.x − 0.45s, c.y − 0.75s, 0.9s × 1.1s): its top half.
        let rx = s * 0.45, ry = s * 0.55
        let ox = c.x, oy = c.y - s * 0.75 + ry
        let k: CGFloat = 0.5522847498
        var arc = Path()
        arc.move(to: CGPoint(x: ox - rx, y: oy))
        arc.addCurve(to: CGPoint(x: ox, y: oy - ry), control1: CGPoint(x: ox - rx, y: oy - k * ry), control2: CGPoint(x: ox - k * rx, y: oy - ry))
        arc.addCurve(to: CGPoint(x: ox + rx, y: oy), control1: CGPoint(x: ox + k * rx, y: oy - ry), control2: CGPoint(x: ox + rx, y: oy - k * ry))
        ctx.stroke(arc, with: .color(.white), style: StrokeStyle(lineWidth: s * 0.22, lineCap: .butt))
    }
}
