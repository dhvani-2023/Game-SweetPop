import SwiftUI
import UIKit
import GameKit

/// Android raw-pixel constants (graphicsLayer translations, stroke widths in px) were tuned at density 2.75.
private let refDensity: CGFloat = BoardPainter.referenceDensity

/**
 * Compose splash shown after the system launch screen: logo with orbiting candies, a progress bar and the version.
 * Stays at least 2.4 s while it pre-renders the candy bitmaps (CandyArt) and generates/loads the audio
 * (SynthBank → AudioManager), then starts the menu music, wipes to `bgTop` and calls [onDone].
 */
struct SplashScreen: View {
    let onDone: () -> Void

    @Environment(\.palette) private var p
    @Environment(AppContainer.self) private var container
    @Environment(\.displayScale) private var displayScale
    @Environment(\.safeDrawingInsets) private var safe

    /// Kotlin `rememberClock()` origin, shared by every animated part of the splash.
    @State private var start = Date()
    @State private var progress: Float = 0
    @State private var status = "Baking fresh candies…"
    @State private var taglineIn = false
    @State private var wipe: Double = 0

    var body: some View {
        ZStack {
            // Orbiting candies behind the logo.
            OrbitCanvas(start: start, front: false)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                SplashLogo(start: start)
                Color.clear.frame(height: 18)
                OutlinedText("Match • Pop • Smile", fontSize: TypeScale.Body, outlineWidth: 2)
                    .opacity(taglineIn ? 1 : 0)
                    .offset(y: taglineIn ? 0 : 20 / refDensity)
                Spacer(minLength: 0)
                LoadingBar(progress: progress, status: status)
                Color.clear.frame(height: 18)
                OutlinedText("v\(Platform.versionName)", fontSize: TypeScale.Caption, outlineWidth: 1.5)
                Color.clear.frame(height: 12)
            }
            .padding(safe)
            OrbitCanvas(start: start, front: true)
            Rectangle()
                .fill(p.bgTop)
                .opacity(wipe)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .onAppear {
            // Kotlin: delay(700); tagline.animateTo(1f, tween(600)).
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.6).delay(0.7)) { taglineIn = true }
        }
        .task { await load() }
    }

    private func setProgress(_ v: Float) {
        // Worker callbacks can land out of order; never let the bar move backwards.
        if v > progress { progress = v }
    }

    private func load() async {
        let startTime = ProcessInfo.processInfo.systemUptime
        let saved = container.save.state // iOS loads the save synchronously (always `loaded`)
        // Pre-render candy bitmaps for the cell sizes the boards will use on this screen
        // (7-wide boards only exist in level 1; other sizes render lazily off the main thread).
        let usable = Float(screenWidthPoints()) - 32
        var sizes: [Int] = [] // linkedSetOf
        func add(_ px: Int) { if !sizes.contains(px) { sizes.append(px) } }
        let widths = saved.highestUnlocked <= 1 ? Array(7...9) : Array(8...9)
        for w in widths { add(Kt.roundToInt(min(usable / Float(w), 52) * Float(displayScale))) }
        add(decorBitmapPx(displayScale))
        await CandyArt.prewarm(sizes: sizes) { f in setProgress(0.55 * f) }
        status = "Tuning the sweet sounds…"
        await SynthBank.ensureGenerated { f in
            Task { @MainActor in setProgress(0.55 + 0.42 * f) }
        }
        container.audio.loadAll()
        setProgress(1)
        status = "Ready to pop!"
        let elapsed = ProcessInfo.processInfo.systemUptime - startTime
        if elapsed < 2.4 { try? await Task.sleep(nanoseconds: UInt64((2.4 - elapsed) * 1_000_000_000)) }
        if Task.isCancelled { return }
        container.audio.playMusic(.MENU)
        // Kotlin: wipe.animateTo(1f, tween(220)); onDone().
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.22)) {
            wipe = 1
        } completion: {
            onDone()
        }
    }
}

/// Kotlin `LocalConfiguration.current.screenWidthDp`.
@MainActor
private func screenWidthPoints() -> CGFloat {
    let scene = UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
    let w = scene?.screen.bounds.width ?? 0
    return w > 0 ? w : 390
}

/// Six candies orbiting the logo on an ellipse, drawn in two passes (behind / in front). Fills the whole screen.
private struct OrbitCanvas: View {
    let start: Date
    let front: Bool

    @Environment(\.displayScale) private var displayScale
    @Environment(\.routeActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let front = self.front
        let decor = decorBitmapPx(displayScale)
        // Ambient decoration: holds still with Reduce Motion (like the Backdrop).
        let still = reduceMotion || GameKit.Motion.reduce
        TimelineView(.animation(minimumInterval: nil, paused: !active || still)) { tl in
            let t = still ? 0 : Float(max(0, tl.date.timeIntervalSince(start)))
            Canvas { ctx, size in
                let cx = Float(size.width) / 2
                let cy = Float(size.height) * 0.42
                let rx = Float(size.width) * 0.47
                let ry = rx * 0.64 * 0.5
                let colors = CandyColor.PLAYABLE
                for i in 0..<6 {
                    let a = t * 0.7 + Float(i) * (Float(Double.pi) * 2 / 6)
                    let depth = Kt.sin(a)
                    if (depth > 0) != front { continue }
                    let x = cx + Kt.cos(a) * rx
                    let y = cy + depth * ry
                    let s = 38 + 14 * depth
                    ctx.drawCandy(
                        colors[i], .NONE, CGFloat(x), CGFloat(y), CGFloat(s),
                        alpha: CGFloat(0.75 + 0.25 * depth), rotationDeg: CGFloat(a * 40), bitmapPx: decor
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// "Sweet / Pop!" with a pulsing glow and two accent candies; elastic scale-in (tween 900 ms) and a slow bob.
private struct SplashLogo: View {
    let start: Date

    @Environment(\.routeActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // With Reduce Motion the logo is simply there: no elastic pop, bob or pulse.
        let still = reduceMotion || GameKit.Motion.reduce
        TimelineView(.animation(minimumInterval: nil, paused: !active || still)) { tl in
            let t = still ? 0 : Float(max(0, tl.date.timeIntervalSince(start)))
            // logoIn.animateTo(1f, tween(900)) → Easing.outElastic(enter).
            let enter = still ? 1 : ComposeCubicBezier.FastOutSlowIn.transform(min(1, t / 0.9))
            let scale = max(0, Easing.outElastic(enter))
            let bob = Kt.sin(t * 1.6) * 14 // px (graphicsLayer translationY)
            ZStack {
                LogoGlow(t: t)
                LogoTitle()
            }
            .frame(width: 320, height: 320)
            .scaleEffect(CGFloat(scale))
            .offset(y: CGFloat(bob) / refDensity)
        }
    }
}

private struct LogoTitle: View {
    var body: some View {
        VStack(spacing: 0) {
            OutlinedText(
                "Sweet", fontSize: 70, brush: Brush.verticalGradient([.white, Color(argb: 0xFFFFB8DC)]),
                outline: Color(argb: 0xFF5A1A7E), outlineWidth: 5, lineHeight: 70
            )
            OutlinedText(
                "Pop!", fontSize: 92, brush: Brush.verticalGradient([Color(argb: 0xFFFFF27A), Color(argb: 0xFFFF9A1F)]),
                outline: Color(argb: 0xFF7A3A12), outlineWidth: 6, lineHeight: 92
            )
        }
    }
}

/// 320 × 320 canvas: pulsing white glow and the wrapped red / blue accent candies.
private struct LogoGlow: View {
    let t: Float

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let t = self.t
        let decor = decorBitmapPx(displayScale)
        Canvas { ctx, size in
            let pulse = 0.85 + 0.15 * Kt.sin(t * 2.4)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            // Brush radius = minDimension / 2 (Compose default); the circle itself pulses.
            let gr = min(size.width, size.height) / 2
            let cr = gr * CGFloat(pulse)
            let g = Gradient(colors: [
                srgbColor(RGBA(1, 1, 1, 0.55 * pulse)), srgbColor(RGBA(1, 1, 1, 0.15)), RGBA.transparent.color,
            ])
            ctx.fill(
                Path(ellipseIn: CGRect(x: c.x - cr, y: c.y - cr, width: cr * 2, height: cr * 2)),
                with: .radialGradient(g, center: c, startRadius: 0, endRadius: gr)
            )
            // accentCandies
            let w = size.width, h = size.height
            ctx.drawCandy(.RED, .WRAPPED, w * 0.18, h * 0.24, 62, rotationDeg: CGFloat(-14 + Kt.sin(t * 2) * 6), bitmapPx: decor)
            ctx.drawCandy(.BLUE, .NONE, w * 0.84, h * 0.74, 56, rotationDeg: CGFloat(10 + Kt.sin(t * 1.7) * 8), bitmapPx: decor)
        }
        .allowsHitTesting(false)
    }
}

/// Pill progress bar (48 pt side margins) with a glossy gold fill, the percentage and a status line.
private struct LoadingBar: View {
    let progress: Float
    let status: String

    var body: some View {
        let frac = CGFloat(progress.coerceIn(0.04, 1))
        VStack(spacing: 0) {
            ZStack {
                Capsule(style: .circular).fill(srgbColor(RGBA(0, 0, 0, 0.28)))
                GeometryReader { g in
                    BarFill()
                        .frame(width: g.size.width * frac, height: g.size.height)
                }
                .padding(4)
                Capsule(style: .circular).strokeBorder(srgbColor(RGBA(1, 1, 1, 0.45)), lineWidth: 2)
                OutlinedText("\(Kt.roundToInt(progress * 100))%", fontSize: 15, outlineWidth: 2)
            }
            .frame(height: 30)
            Color.clear.frame(height: 8)
            OutlinedText(status, fontSize: TypeScale.Label, outlineWidth: 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 48)
    }
}

private struct BarFill: View {
    private static let gradient = Gradient(colors: [Color(argb: 0xFFFFF1A8), Color(argb: 0xFFFFC12E), Color(argb: 0xFFFF9E1B)])

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let pill = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: min(w, h) / 2, style: .circular)
            ctx.clip(to: pill)
            ctx.fill(pill, with: .linearGradient(Self.gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            let sw = max(0, w - h * 0.8)
            let shine = CGRect(x: h * 0.4, y: h * 0.14, width: sw, height: h * 0.28)
            ctx.fill(
                Path(roundedRect: shine, cornerRadius: min(h, shine.height / 2, sw / 2), style: .circular),
                with: RGBA.white.shading(alpha: 0.45)
            )
        }
    }
}
