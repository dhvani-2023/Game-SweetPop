import SwiftUI
import GameKit

// Port notes: every dialog is a full-screen `SweetDialog` overlay; place it in a full-screen ZStack above the
// screen. Parameters keep the Kotlin names and order (the `modifier` parameters are dropped). Click sounds and
// haptics come from `AudioManager.shared` / `Haptics.shared` (Kotlin `LocalAudio` / `LocalHaptics`).

/**
 * Hook for a future AdMob rewarded "+5 moves" button on the Lose dialog.
 * Set [available] to true once a rewarded ad is loaded; the button then calls the continue callback.
 */
enum RewardedAds {
    nonisolated(unsafe) static var available: Bool = false
}

/// Icon tile + label + toggle switch row.
struct ToggleRow: View {
    let icon: ImageVector
    let color: Color
    let label: String
    let checked: Bool
    let onChange: (Bool) -> Void

    @Environment(\.palette) private var p

    init(icon: ImageVector, color: Color, label: String, checked: Bool, onChange: @escaping (Bool) -> Void) {
        self.icon = icon
        self.color = color
        self.label = label
        self.checked = checked
        self.onChange = onChange
    }

    /// Kotlin positional call `ToggleRow(icon, color, label, checked, onChange)`.
    init(_ icon: ImageVector, _ color: Color, _ label: String, _ checked: Bool, _ onChange: @escaping (Bool) -> Void) {
        self.init(icon: icon, color: color, label: label, checked: checked, onChange: onChange)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            IconTile(icon, color)
            Spacer().frame(width: 14)
            BodyText(label, color: p.text, textAlign: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            ToggleSwitch(checked, onCheckedChange: onChange)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}

/// Kotlin `infiniteRepeatable(tween(ms, EaseInOutSine), Reverse)` scale pulse; still under Reduce Motion.
private struct Pulse: ViewModifier {
    let from: CGFloat
    let to: CGFloat
    let seconds: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion || Motion.reduce {
            content
        } else {
            content.phaseAnimator([from, to]) { c, s in
                c.scaleEffect(s)
            } animation: { _ in
                .timingCurve(0.37, 0, 0.63, 1, duration: seconds)
            }
        }
    }
}

private extension View {
    func pulsing(_ from: CGFloat, _ to: CGFloat, seconds: Double) -> some View {
        modifier(Pulse(from: from, to: to, seconds: seconds))
    }
}

/// A count that animates its displayed value (Compose `Animatable<Float>` shown with `roundToInt()`).
private struct CountingOutlinedText: View, Animatable {
    var value: Double
    let fontSize: CGFloat
    let color: Color
    let outline: Color
    let outlineWidth: CGFloat

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        OutlinedText(
            GoalTracker.formatNumber(Kt.roundToInt(Float(value))), fontSize: fontSize, color: color, outline: outline,
            outlineWidth: outlineWidth
        )
    }
}

// ---------------------------------------------------------------- pause

struct PauseDialog: View {
    let visible: Bool
    let save: SaveData
    let onMusic: (Bool) -> Void
    let onSound: (Bool) -> Void
    let onVibration: (Bool) -> Void
    let onResume: () -> Void
    let onRestart: () -> Void
    let onMap: () -> Void

    @Environment(\.palette) private var p

    init(
        visible: Bool, save: SaveData, onMusic: @escaping (Bool) -> Void, onSound: @escaping (Bool) -> Void,
        onVibration: @escaping (Bool) -> Void, onResume: @escaping () -> Void, onRestart: @escaping () -> Void,
        onMap: @escaping () -> Void
    ) {
        self.visible = visible
        self.save = save
        self.onMusic = onMusic
        self.onSound = onSound
        self.onVibration = onVibration
        self.onResume = onResume
        self.onRestart = onRestart
        self.onMap = onMap
    }

    var body: some View {
        SweetDialog(visible, onDismissRequest: onResume, title: "Paused", ribbonColor: p.accent2) {
            ToggleRow(Icons.Music, p.accent, "Music", save.music, onMusic)
            ToggleRow(Icons.Sound, p.accent2, "Sound", save.sfx, onSound)
            ToggleRow(Icons.Vibration, p.sky, "Vibration", save.vibration, onVibration)
            Spacer().frame(height: 14)
            CandyButton3D("Resume", onClick: onResume, color: p.success, icon: Icons.Play)
            Spacer().frame(height: 10)
            HStack(spacing: 10) {
                CandyButton3D("Restart", onClick: onRestart, color: p.accent2, height: 58, fontSize: 20, icon: Icons.Replay)
                CandyButton3D("Map", onClick: onMap, color: p.danger, height: 58, fontSize: 20, icon: Icons.Map)
            }
        }
    }
}

// ---------------------------------------------------------------- confirm

struct ConfirmDialog: View {
    let visible: Bool
    let title: String
    let message: String
    let yes: String
    let no: String
    let destructive: Bool
    let onYes: () -> Void
    let onNo: () -> Void

    @Environment(\.palette) private var p

    init(
        visible: Bool, title: String, message: String, yes: String, no: String, destructive: Bool,
        onYes: @escaping () -> Void, onNo: @escaping () -> Void
    ) {
        self.visible = visible
        self.title = title
        self.message = message
        self.yes = yes
        self.no = no
        self.destructive = destructive
        self.onYes = onYes
        self.onNo = onNo
    }

    var body: some View {
        SweetDialog(visible, onDismissRequest: onNo, title: title, ribbonColor: destructive ? p.danger : p.accent2) {
            BodyText(message, color: p.text)
            Spacer().frame(height: 18)
            HStack(spacing: 10) {
                CandyButton3D(no, onClick: onNo, color: p.accent2, height: 58, fontSize: 22)
                CandyButton3D(yes, onClick: onYes, color: destructive ? p.danger : p.success, height: 58, fontSize: 22)
            }
        }
    }
}

// ---------------------------------------------------------------- win

struct WinDialog: View {
    let visible: Bool
    let levelNumber: Int
    let result: GameResult?
    let isLastLevel: Bool
    let onNext: () -> Void
    let onMap: () -> Void
    /// iOS extras: coins the win paid ("+N coins"); 0 hides the row.
    let coins: Int

    /// Kotlin `rememberLast(result)`: keeps showing the last result while the dialog animates out.
    @State private var last: GameResult?

    init(
        visible: Bool, levelNumber: Int, result: GameResult?, isLastLevel: Bool, onNext: @escaping () -> Void,
        onMap: @escaping () -> Void, coins: Int = 0
    ) {
        self.visible = visible
        self.levelNumber = levelNumber
        self.result = result
        self.isLastLevel = isLastLevel
        self.onNext = onNext
        self.onMap = onMap
        self.coins = coins
    }

    var body: some View {
        ZStack {
            if let r = result ?? last {
                WinDialogBody(visible: visible, levelNumber: levelNumber, r: r, isLastLevel: isLastLevel, onNext: onNext, onMap: onMap, coins: coins)
            }
        }
        .onChange(of: result, initial: true) { _, new in
            if let new { last = new }
        }
    }
}

/// Confetti + sparkle layer of the win dialog, on its own frame loop (Kotlin: `LaunchedEffect(visible)` loop).
@MainActor
private final class WinFx {
    let loop = GameLoop()
    let fx = Effects()
    /// Size and global origin of the full-screen front canvas.
    var size: CGSize = .zero
    var origin: CGPoint = .zero
    /// Star centres in global coordinates.
    var starCenters = [CGPoint](repeating: .zero, count: 3)
    private var confettiDone = false

    init() {
        loop.onTick = { [weak self] dt in self?.step(Float(dt)) }
    }

    func start() {
        fx.clear()
        confettiDone = false
        loop.start()
    }

    func stop() {
        loop.stop()
    }

    private func step(_ dt: Float) {
        fx.update(dt.coerceAtMost(0.05))
        if !confettiDone && fx.time > 0.3 && size.width > 0 {
            fx.confetti(Float(size.width), Float(size.height))
            confettiDone = true
        }
    }

    func sparkleAtStar(_ i: Int) {
        let c = starCenters[i]
        fx.sparkles(Float(c.x - origin.x), Float(c.y - origin.y), 8, 40 * fx.density, 14 * fx.density, Color(argb: 0xFFFFF4B0))
    }
}

private struct WinFxCanvas: View {
    let model: WinFx

    var body: some View {
        let frameTick = model.loop.frame
        let model = self.model
        Canvas { ctx, _ in
            _ = frameTick // capture the changing frame so SwiftUI redraws this Canvas every tick
            model.fx.draw(ctx)
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { r in
            model.size = r.size
            model.origin = r.origin
        }
        .allowsHitTesting(false)
    }
}

private struct WinDialogBody: View {
    let visible: Bool
    let levelNumber: Int
    let r: GameResult
    let isLastLevel: Bool
    let onNext: () -> Void
    let onMap: () -> Void
    let coins: Int

    @Environment(\.palette) private var p
    @State private var model = WinFx()
    /// Per star: shown at all (Kotlin scale > 0) and a counter that replays its pop.
    @State private var revealed = [false, false, false]
    @State private var popSeq = [0, 0, 0]
    @State private var shown: Double = 0

    private struct ScoreKey: Equatable {
        let visible: Bool
        let score: Int
    }

    var body: some View {
        let model = self.model
        SweetDialog(visible, onDismissRequest: onMap, title: "Sweet Win!", ribbonColor: p.success) {
            dialogContent
        } front: {
            WinFxCanvas(model: model)
        }
        .onChange(of: visible, initial: true) { _, v in
            if v { model.start() } else { model.stop() }
        }
        .onDisappear { model.stop() }
        .task(id: visible) { await revealStars() }
        .task(id: ScoreKey(visible: visible, score: r.score)) { await countScore() }
    }

    @ViewBuilder
    private var dialogContent: some View {
        ZStack {
            GoldenSunburst()
                .frame(maxWidth: 260)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    winStar(i)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        BodyText("Level \(levelNumber) complete!", color: p.subText, fontSize: TypeScale.Label)
        Spacer().frame(height: 4)
        CountingOutlinedText(value: shown, fontSize: 40, color: p.gold, outline: shade(p.gold, 0.5), outlineWidth: 2.5)
        if r.newBest {
            OutlinedText("New best score!", fontSize: 18, outline: shade(p.accent, 0.5), outlineWidth: 2)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Capsule(style: .circular).fill(LinearGradient(colors: [p.accent, p.accent2], startPoint: .leading, endPoint: .trailing)))
                .pulsing(0.94, 1.06, seconds: 0.6)
                .padding(.top, 6)
        }
        if coins > 0 {
            WinCoinsRow(amount: coins, visible: visible)
                .padding(.top, 8)
        }
        Spacer().frame(height: 18)
        if isLastLevel {
            CandyButton3D("Map", onClick: onMap, color: p.success, icon: Icons.Map)
        } else {
            CandyButton3D("Next Level", onClick: onNext, color: p.success, icon: Icons.Play, breathing: true)
            Spacer().frame(height: 10)
            CandyButton3D("Map", onClick: onMap, color: p.accent2, height: 58, fontSize: 22, icon: Icons.Map)
        }
    }

    private func winStar(_ i: Int) -> some View {
        let big: CGFloat = i == 1 ? 84 : 66
        let model = self.model
        return ZStack {
            StarIcon(lit: false, size: big)
            if i < r.stars {
                StarIcon(lit: true, size: big)
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: popSeq[i]) { content, s in
                        content.scaleEffect(s)
                    } keyframes: { _ in
                        // scale.snapTo(2.4f); scale.animateTo(1f, spring(dampingRatio = 0.45f, stiffness = 320f))
                        MoveKeyframe(CGFloat(2.4))
                        SpringKeyframe(CGFloat(1), spring: composeSpring(dampingRatio: 0.45, stiffness: 320))
                    }
                    .opacity(revealed[i] ? 1 : 0)
            }
        }
        .frame(width: big, height: big)
        .onGeometryChange(for: CGPoint.self) { proxy in
            let f = proxy.frame(in: .global)
            return CGPoint(x: f.midX, y: f.midY)
        } action: { c in
            model.starCenters[i] = c
        }
        .padding(.bottom, i == 1 ? 26 : 4)
    }

    /// Kotlin: per star `delay(450 + i * 380)`, then pop with a sound, a buzz and sparkles.
    private func revealStars() async {
        guard visible else { return }
        revealed = [false, false, false]
        let start = ContinuousClock.now
        for i in 0..<3 {
            try? await Task.sleep(until: start.advanced(by: .milliseconds(450 + i * 380)), clock: .continuous)
            if Task.isCancelled { return }
            if i < r.stars {
                revealed[i] = true
                popSeq[i] &+= 1
                AudioManager.shared.play(.STAR, rate: 1 + 0.14 * Float(i))
                Haptics.shared.medium()
                model.sparkleAtStar(i)
            }
        }
    }

    /// Kotlin: `shown.snapTo(0f); delay(400); shown.animateTo(score, tween(1100))`.
    private func countScore() async {
        guard visible else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { shown = 0 }
        try? await Task.sleep(for: .milliseconds(400))
        if Task.isCancelled { return }
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 1.1)) { shown = Double(r.score) }
    }
}

/// Slowly rotating golden rays behind the win stars.
private struct GoldenSunburst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let glow = Gradient(colors: [srgbColor(RGBA(argb: 0xFFFFE27A).with(alpha: 0.55)), .clear])
    private static let ray = Gradient(colors: [srgbColor(RGBA(argb: 0xFFFFD34D).with(alpha: 0.55)), .clear])

    /// The 16 rays around (0, 0) with radius 1; they never overlap, so one fill equals 16.
    private static let rays: Path = {
        var p = Path()
        for i in 0..<16 {
            let a = Float(Double(i) * 2 * Double.pi / 16)
            let w: Float = 0.09
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: CGFloat(Kt.cos(a - w)), y: CGFloat(Kt.sin(a - w))))
            p.addLine(to: CGPoint(x: CGFloat(Kt.cos(a + w)), y: CGFloat(Kt.sin(a + w))))
            p.closeSubpath()
        }
        return p
    }()

    var body: some View {
        ClockView(paused: reduceMotion || Motion.reduce) { t in
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2
                guard r > 0 else { return }
                ctx.fill(
                    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                    with: .radialGradient(Self.glow, center: c, startRadius: 0, endRadius: r)
                )
                var g = ctx
                g.translateBy(x: c.x, y: c.y)
                g.rotate(by: .degrees(Double(t * 18)))
                g.scaleBy(x: r, y: r)
                g.fill(Self.rays, with: .radialGradient(Self.ray, center: .zero, startRadius: 0, endRadius: 1))
            }
        }
        .allowsHitTesting(false)
    }
}

// ---------------------------------------------------------------- lose

struct LoseDialog: View {
    let visible: Bool
    let summary: String
    let livesLeft: Int
    let onRetry: () -> Void
    let onMap: () -> Void
    let onExtraMoves: () -> Void
    /// iOS extras: the "+5 Moves" offer (free once per attempt, then booster or coins) shown where Android keeps
    /// its hidden rewarded button; nil = Android behaviour.
    let extraMoves: ExtraMovesOffer?

    @Environment(\.palette) private var p

    init(
        visible: Bool, summary: String, livesLeft: Int, onRetry: @escaping () -> Void, onMap: @escaping () -> Void,
        onExtraMoves: @escaping () -> Void, extraMoves: ExtraMovesOffer? = nil
    ) {
        self.visible = visible
        self.summary = summary
        self.livesLeft = livesLeft
        self.onRetry = onRetry
        self.onMap = onMap
        self.onExtraMoves = onExtraMoves
        self.extraMoves = extraMoves
    }

    var body: some View {
        SweetDialog(visible, onDismissRequest: onMap, title: "Out of Moves", ribbonColor: p.danger) {
            SadCandy()
                .frame(width: 96, height: 96)
            OutlinedText("So close!", fontSize: TypeScale.Headline, color: p.danger, outline: shade(p.danger, 0.5), outlineWidth: 2.5)
            Spacer().frame(height: 4)
            BodyText(summary, color: p.text)
            Spacer().frame(height: 8)
            HStack(alignment: .center, spacing: 0) {
                BodyText("−1", color: p.danger)
                Spacer().frame(width: 4)
                HeartBadge(count: livesLeft, size: 32)
                Spacer().frame(width: 6)
                BodyText("(\(livesLeft) left)", color: p.subText, fontSize: TypeScale.Label)
            }
            Spacer().frame(height: 16)
            if let offer = extraMoves {
                ExtraMovesButton(offer: offer)
                Spacer().frame(height: 10)
            } else if RewardedAds.available {
                CandyButton3D("+5 Moves", onClick: onExtraMoves, color: p.gold, height: 58, fontSize: 22, icon: Icons.Play)
                Spacer().frame(height: 10)
            }
            CandyButton3D("Try Again", onClick: onRetry, color: p.accent, icon: Icons.Replay)
            Spacer().frame(height: 10)
            CandyButton3D("Map", onClick: onMap, color: p.accent2, height: 58, fontSize: 22, icon: Icons.Map)
        }
    }
}

/// A blue lollipop with a sad face, wobbling. Fills the frame it is given (Kotlin `SadCandy(Modifier.size(96.dp))`).
struct SadCandy: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    private static let ink = RGBA(argb: 0xFF2A1240)
    private static let tear = RGBA(argb: 0xFF9FE3FF)

    /// Mouth in face units (u = 1) around the candy centre.
    private static let mouth: Path = {
        var p = Path()
        p.move(to: CGPoint(x: -0.22, y: 0.42))
        p.addQuadCurve(to: CGPoint(x: 0.22, y: 0.42), control: CGPoint(x: 0, y: 0.2))
        return p
    }()

    init() {}

    var body: some View {
        let decor = decorBitmapPx(displayScale)
        GeometryReader { geo in
            let cell = min(geo.size.width, geo.size.height)
            // The candy bitmap is 1.2 × the cell and wobbles: draw past the frame like an unclipped Compose canvas.
            let m = cell * 0.3
            ClockView(paused: reduceMotion || Motion.reduce) { t in
                Canvas { ctx, size in
                    Self.draw(ctx, CGPoint(x: size.width / 2, y: size.height / 2), cell, t, decor)
                }
            }
            .frame(width: geo.size.width + m * 2, height: geo.size.height + m * 2)
            .offset(x: -m, y: -m)
        }
        .allowsHitTesting(false)
    }

    private static func draw(_ ctx: GraphicsContext, _ c: CGPoint, _ cell: CGFloat, _ t: Float, _ decor: Int) {
        guard cell > 0 else { return }
        let rot = Kt.sin(t * 3.2) * 10
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .degrees(Double(rot)))
        g.translateBy(x: -c.x, y: -c.y)
        g.drawCandy(.BLUE, .NONE, c.x, c.y, cell, bitmapPx: decor)
        let u = cell * 0.45
        let eyeY = c.y - u * 0.05
        eye(g, c.x - 0.28 * u, eyeY, u)
        eye(g, c.x + 0.28 * u, eyeY, u)
        var face = g
        face.translateBy(x: c.x, y: c.y)
        face.scaleBy(x: u, y: u)
        face.stroke(mouth, with: ink.shading, style: StrokeStyle(lineWidth: 0.07, lineCap: .round))
        let tr = u * 0.07
        let ty = eyeY + u * 0.22 + CGFloat(Kt.rem(t * 0.6, 1)) * u * 0.25
        g.fill(Path(ellipseIn: CGRect(x: c.x + u * 0.36 - tr, y: ty - tr, width: tr * 2, height: tr * 2)), with: tear.shading)
    }

    private static func eye(_ g: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ u: CGFloat) {
        let r1 = u * 0.15
        g.fill(Path(ellipseIn: CGRect(x: x - r1, y: y - r1, width: r1 * 2, height: r1 * 2)), with: RGBA.white.shading)
        let r2 = u * 0.08
        let py = y + u * 0.04
        g.fill(Path(ellipseIn: CGRect(x: x - r2, y: py - r2, width: r2 * 2, height: r2 * 2)), with: ink.shading)
    }
}

// ---------------------------------------------------------------- lives

struct NoLivesDialog: View {
    let visible: Bool
    let save: SaveData
    let onOk: () -> Void

    @Environment(\.palette) private var p
    @RememberNow private var now: Int64

    init(visible: Bool, save: SaveData, onOk: @escaping () -> Void) {
        self.visible = visible
        self.save = save
        self.onOk = onOk
    }

    /// Kotlin positional call `NoLivesDialog(visible, save) { … }`.
    init(_ visible: Bool, _ save: SaveData, _ onOk: @escaping () -> Void) {
        self.init(visible: visible, save: save, onOk: onOk)
    }

    var body: some View {
        let now = self.now
        SweetDialog(visible, onDismissRequest: onOk, title: "Out of Lives", ribbonColor: p.danger) {
            PulsingHeart(count: save.livesNow(now: now).lives)
            Spacer().frame(height: 8)
            BodyText("Take a sweet break! Next life in", color: p.text)
            let s = save.livesNow(now: now)
            OutlinedText(Lives.timerText(s, now), fontSize: TypeScale.Title, color: p.accent, outline: shade(p.accent, 0.5), outlineWidth: 2.5)
            Spacer().frame(height: 16)
            CandyButton3D("OK", onClick: onOk, color: p.success)
        }
    }
}

struct LivesInfoDialog: View {
    let visible: Bool
    let save: SaveData
    let onClose: () -> Void

    @Environment(\.palette) private var p
    @RememberNow private var now: Int64

    init(visible: Bool, save: SaveData, onClose: @escaping () -> Void) {
        self.visible = visible
        self.save = save
        self.onClose = onClose
    }

    /// Kotlin positional call `LivesInfoDialog(visible, save) { … }`.
    init(_ visible: Bool, _ save: SaveData, _ onClose: @escaping () -> Void) {
        self.init(visible: visible, save: save, onClose: onClose)
    }

    var body: some View {
        let now = self.now
        let s = save.livesNow(now: now)
        SweetDialog(visible, onDismissRequest: onClose, title: "Lives", ribbonColor: p.accent, showClose: true) {
            PulsingHeart(count: s.lives)
            Spacer().frame(height: 6)
            if s.isFull {
                BodyText("Your lives are full!", color: p.text)
            } else {
                BodyText("Next life in", color: p.text)
                OutlinedText(Lives.timerText(s, now), fontSize: TypeScale.Title, color: p.accent, outline: shade(p.accent, 0.5), outlineWidth: 2.5)
            }
            Spacer().frame(height: 6)
            BodyText("One life refills every 20 minutes, up to \(Lives.MAX).", color: p.subText, fontSize: TypeScale.Label)
            Spacer().frame(height: 16)
            CandyButton3D("OK", onClick: onClose, color: p.success)
        }
    }
}

private struct PulsingHeart: View {
    let count: Int

    var body: some View {
        // infiniteRepeatable(tween(520, EaseInOutSine), Reverse) between 0.92 and 1.08.
        HeartBadge(count: count, size: 84)
            .pulsing(0.92, 1.08, seconds: 0.52)
    }
}

// ---------------------------------------------------------------- level start

struct LevelStartDialog: View {
    let level: Level?
    let starsEarned: Int
    let best: Int
    let onPlay: (Int) -> Void
    let onClose: () -> Void

    @Environment(\.palette) private var p
    /// Kotlin `rememberLast(level)`.
    @State private var last: Level?

    init(level: Level?, starsEarned: Int, best: Int, onPlay: @escaping (Int) -> Void, onClose: @escaping () -> Void) {
        self.level = level
        self.starsEarned = starsEarned
        self.best = best
        self.onPlay = onPlay
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            if let l = level ?? last {
                dialog(l)
            }
        }
        .onChange(of: level?.number, initial: true) { _, _ in
            if let level { last = level }
        }
    }

    private func dialog(_ l: Level) -> some View {
        let tricky = l.isTricky
        let onPlay = self.onPlay
        return SweetDialog(
            level != nil, onDismissRequest: onClose, title: "Level \(l.number)",
            ribbonColor: tricky ? CandyColors.nodeTricky : p.accent, showClose: true
        ) {
            HStack(alignment: .bottom, spacing: 4) {
                StarIcon(starsEarned >= 1, 54)
                StarIcon(starsEarned >= 2, 68)
                    .offset(y: -14)
                StarIcon(starsEarned >= 3, 54)
            }
            if tricky {
                OutlinedText("Tricky Level!", fontSize: 16, outline: shade(CandyColors.nodeTricky, 0.5), outlineWidth: 2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .circular)
                            .fill(LinearGradient(colors: [CandyColors.nodeTricky, p.accent], startPoint: .leading, endPoint: .trailing))
                    )
                    .padding(.top, 2)
                    .padding(.bottom, 6)
            }
            VStack(alignment: .center, spacing: 0) {
                BodyText(GoalTracker.goalDescription(l), color: p.text)
                Spacer().frame(height: 8)
                HStack(alignment: .center, spacing: 16) {
                    switch l.goal {
                    case .COLLECT:
                        ForEach(l.collect.indices, id: \.self) { i in
                            GoalCount(goal: .COLLECT, color: l.collect[i].color, text: "×\(l.collect[i].count)")
                        }
                    case .JELLY:
                        GoalCount(goal: .JELLY, color: nil, text: "×\(l.jelly.filter { $0 > 0 }.count)")
                    case .FROSTING:
                        GoalCount(goal: .FROSTING, color: nil, text: "×\(l.frosting.filter { $0 > 0 }.count)")
                    case .SCORE:
                        GoalCount(goal: .SCORE, color: nil, text: GoalTracker.formatNumber(l.scoreTarget))
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 20, style: .circular).fill(p.panelAlt))
            .padding(.top, 6)
            Spacer().frame(height: 10)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                BodyText("\(l.moves) moves", color: p.text, fontSize: TypeScale.Label)
                Spacer(minLength: 0)
                BodyText("Best: \(GoalTracker.formatNumber(best))", color: p.subText, fontSize: TypeScale.Label)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            Spacer().frame(height: 16)
            CandyButton3D("Play!", onClick: { onPlay(l.number) }, color: p.success, icon: Icons.Play, breathing: true)
        }
    }
}

private struct GoalCount: View {
    let goal: GoalType
    let color: CandyColor?
    let text: String

    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            GoalIcon(goal: goal, color: color, size: 40)
            Spacer().frame(width: 4)
            BodyText(text, color: p.text)
        }
    }
}
