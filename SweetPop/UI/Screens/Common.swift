import SwiftUI
import Observation
import GameKit

let HeartRed = Color(argb: 0xFFFF4D63)
let StarGold = Color(argb: 0xFFFFC12E)

/// Compose `spring(dampingRatio, stiffness)` as a SwiftUI `Spring` (mass 1), for keyframe animations.
func composeSpring(dampingRatio: Double, stiffness: Double) -> Spring {
    Spring(mass: 1, stiffness: stiffness, damping: 2 * dampingRatio * stiffness.squareRoot())
}

// ---------------------------------------------------------------- rememberNow

/**
 * Wall-clock millis, refreshed every [periodMs] (for lives timers). Kotlin `val now by rememberNow()`:
 * `@RememberNow private var now: Int64` (or `@RememberNow(periodMs: 500)`); `@rememberNow` also works.
 */
@propertyWrapper
struct RememberNow: DynamicProperty {
    @State private var ticker = NowTicker()
    private let periodMs: Int64

    init(periodMs: Int64 = 1000) {
        self.periodMs = periodMs
    }

    var wrappedValue: Int64 { ticker.now }

    func update() {
        ticker.start(periodMs)
    }
}

/// Kotlin spelling of the property wrapper.
typealias rememberNow = RememberNow

/// Main-run-loop timer behind [RememberNow]; stops by itself once nothing holds it any more.
@Observable
final class NowTicker {
    private(set) var now: Int64 = Days.nowMillis()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var periodMs: Int64 = 0

    func start(_ periodMs: Int64) {
        if timer != nil && self.periodMs == periodMs { return }
        timer?.invalidate()
        self.periodMs = periodMs
        let t = Timer(timeInterval: Double(max(1, periodMs)) / 1000, repeats: true) { [weak self] t in
            guard let self else {
                t.invalidate()
                return
            }
            self.now = Days.nowMillis()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

// ---------------------------------------------------------------- stars

func starPath(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, inner: CGFloat = 0.48) -> Path {
    var p = Path()
    for i in 0..<10 {
        let a = Float(-Double.pi / 2 + Double(i) * Double.pi / 5)
        let rr = i % 2 == 0 ? r : r * inner
        let x = cx + rr * CGFloat(Kt.cos(a))
        let y = cy + rr * CGFloat(Kt.sin(a))
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
}

private enum StarPaint {
    static let rim = RGBA(argb: 0xFFB26A00)
    static let socket = RGBA(argb: 0xFF4A1C6E)
    static let body = Gradient(colors: [Color(argb: 0xFFFFF1A8), StarGold, Color(argb: 0xFFFF9E1B)])
}

extension GraphicsContext {
    /// Glossy gold star (or an empty socket when [lit] is false).
    func drawStar(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ lit: Bool, alpha: CGFloat = 1) {
        let p = starPath(cx, cy, r)
        let a = Float(alpha)
        if lit {
            stroke(p, with: StarPaint.rim.shading(alpha: a), style: StrokeStyle(lineWidth: r * 0.22, lineJoin: .round))
            var g = self
            g.opacity *= Double(alpha)
            g.fill(p, with: .linearGradient(StarPaint.body, startPoint: CGPoint(x: cx, y: cy - r), endPoint: CGPoint(x: cx, y: cy + r)))
            fill(starPath(cx - r * 0.12, cy - r * 0.18, r * 0.42), with: RGBA.white.shading(alpha: 0.45 * a))
        } else {
            stroke(p, with: StarPaint.socket.shading(alpha: 0.35 * a), style: StrokeStyle(lineWidth: r * 0.2, lineJoin: .round))
            fill(p, with: RGBA.white.shading(alpha: 0.35 * a))
        }
    }
}

/// Compose canvases don't clip their drawing: draw into a frame [margin] larger on every side, laid out at [size].
private extension View {
    func unclippedCanvas(_ size: CGFloat, margin: CGFloat) -> some View {
        frame(width: size + margin * 2, height: size + margin * 2).padding(-margin)
    }
}

struct StarIcon: View {
    let lit: Bool
    let size: CGFloat

    init(lit: Bool, size: CGFloat) {
        self.lit = lit
        self.size = size
    }

    /// Kotlin positional call `StarIcon(lit, size)`.
    init(_ lit: Bool, _ size: CGFloat) {
        self.init(lit: lit, size: size)
    }

    var body: some View {
        let lit = self.lit
        let size = self.size
        let m = size * 0.1
        Canvas { ctx, s in
            ctx.drawStar(s.width / 2, s.height / 2, size * 0.48, lit)
        }
        .unclippedCanvas(size, margin: m)
        .allowsHitTesting(false)
    }
}

/// Small icon for a goal: candy for collect, jelly square, frosting block, or a star for score.
struct GoalIcon: View {
    let goal: GoalType
    let color: CandyColor?
    let size: CGFloat

    @Environment(\.displayScale) private var displayScale
    @Environment(AppContainer.self) private var container
    /// Bumped once a candy bitmap that was missing has been rendered, so the canvas redraws with it.
    @State private var artTick = 0

    init(goal: GoalType, color: CandyColor?, size: CGFloat) {
        self.goal = goal
        self.color = color
        self.size = size
    }

    /// Kotlin positional call `GoalIcon(goal, color, size)`.
    init(_ goal: GoalType, _ color: CandyColor?, _ size: CGFloat) {
        self.init(goal: goal, color: color, size: size)
    }

    var body: some View {
        let goal = self.goal
        let candy = color ?? .RED
        let s = size
        let decor = decorBitmapPx(displayScale)
        let tick = artTick
        // iOS extras: collect goals carry the colour-blind symbol too.
        let colorBlind = Features.colorBlind && container.save.extras.colorBlind
        Canvas { ctx, cs in
            _ = tick
            let c = CGPoint(x: cs.width / 2, y: cs.height / 2)
            switch goal {
            case .COLLECT:
                ctx.drawCandy(candy, .NONE, c.x, c.y, s * 1.05, bitmapPx: decor)
                if colorBlind { ctx.drawColorBlindSymbol(candy, c.x, c.y, s * 1.05) }
            case .JELLY: ctx.drawJelly(c.x, c.y, s * 1.05, 2)
            case .FROSTING: ctx.drawFrosting(c.x, c.y, s * 0.95, 1, 3)
            case .SCORE: ctx.drawStar(c.x, c.y, s * 0.46, true)
            }
        }
        .unclippedCanvas(s, margin: s * 0.25)
        .allowsHitTesting(false)
        .task(id: decor * 8 + candy.ordinal) {
            guard goal == .COLLECT, !CandyArt.isReady(decor) else { return }
            await Task.detached(priority: .userInitiated) { _ = CandyArt.bitmap(candy, .NONE, decor) }.value
            artTick &+= 1
        }
    }
}

/// Heart with the life count written inside it.
struct HeartBadge: View {
    let count: Int
    var size: CGFloat = 44

    init(count: Int, size: CGFloat = 44) {
        self.count = count
        self.size = size
    }

    /// Kotlin positional call `HeartBadge(count, size)`.
    init(_ count: Int, _ size: CGFloat = 44) {
        self.init(count: count, size: size)
    }

    var body: some View {
        ZStack {
            Icon(Icons.Heart, contentDescription: nil, tint: HeartRed)
                .frame(width: size, height: size)
            OutlinedText(String(count), fontSize: size * 0.4, outline: Color(argb: 0xFF8E1028), outlineWidth: 2)
                .padding(.bottom, 2)
        }
        .frame(width: size, height: size)
    }
}

/// Back button + large outlined title used by Settings and documents.
struct ScreenHeader: View {
    let title: String
    let onBack: () -> Void

    @Environment(\.palette) private var p

    init(title: String, onBack: @escaping () -> Void) {
        self.title = title
        self.onBack = onBack
    }

    /// Kotlin positional call `ScreenHeader(title, onBack)`.
    init(_ title: String, _ onBack: @escaping () -> Void) {
        self.init(title: title, onBack: onBack)
    }

    var body: some View {
        HStack(spacing: 0) {
            IconButton3D(Icons.Back, onClick: onBack, color: p.accent2, size: 52, contentDescription: "Back")
            Spacer().frame(width: 14)
            OutlinedText(title, fontSize: TypeScale.Title, brush: TitleGradient, maxLines: 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}
