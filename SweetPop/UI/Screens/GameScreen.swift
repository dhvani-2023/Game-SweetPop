import SwiftUI
import UIKit
import GameKit

/**
 * One level: HUD, board, bottom bar, the effects layer, the intro banner and every game dialog.
 *
 * iOS port notes:
 * • Kotlin `viewModel(key = "game-$levelNumber")` → a `GameViewModel` created when the screen appears (one per
 *   level number) and cleared when it disappears.
 * • The game clock is the view model's GameKit `GameLoop`, started on appear (Kotlin's `withFrameNanos` loop).
 * • The column respects the safe area (Kotlin `windowInsetsPadding(WindowInsets.safeDrawing)`); the effects layer
 *   and dialogs cover the whole screen. Positions are measured in the [rootSpace] coordinate space.
 * • There is no hardware back button: the pause button is the way out (Kotlin `BackHandler` → pause).
 */
struct GameScreen: View {
    let levelNumber: Int
    let onMap: () -> Void
    let onNextLevel: (Int) -> Void

    /// Named coordinate space of the screen root; board, goal slots and the effects layer report positions in it.
    static let rootSpace = "gameRoot"

    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm: GameViewModel?
    /// Counted in [GameScreenPresence] (guards against an extra onAppear without onDisappear).
    @State private var present = false

    init(levelNumber: Int, onMap: @escaping () -> Void, onNextLevel: @escaping (Int) -> Void) {
        self.levelNumber = levelNumber
        self.onMap = onMap
        self.onNextLevel = onNextLevel
    }

    var body: some View {
        ZStack {
            if let vm {
                GameContent(vm: vm, onMap: onMap, onNextLevel: onNextLevel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: enter)
        .onDisappear(perform: leaveScreen)
        .onChange(of: levelNumber) { _, _ in
            guard vm != nil else { return }
            startLevel()
        }
        .onChange(of: scenePhase) { _, phase in
            // Kotlin LifecycleEventEffect(ON_STOP).
            if phase == .background { vm?.onBackground() }
        }
    }

    /// Kotlin `LaunchedEffect(Unit)` + `DisposableEffect(Unit)` start.
    private func enter() {
        if !present {
            present = true
            GameScreenPresence.count += 1
        }
        UIApplication.shared.isIdleTimerDisabled = true
        startLevel()
    }

    private func startLevel() {
        if let old = vm, old.levelNumber == levelNumber, !old.isCleared {
            old.loop.start()
        } else {
            vm?.onCleared()
            let fresh = GameViewModel(container: container, levelNumber: levelNumber)
            vm = fresh
            fresh.loop.start()
        }
        container.save.setLastPlayed(levelNumber)
        container.audio.playMusic(.GAME)
    }

    /// Kotlin `onDispose` + `onCleared()`. The (stopped) board stays drawn while the screen fades out.
    private func leaveScreen() {
        vm?.onCleared()
        container.audio.duck(false)
        if present {
            present = false
            GameScreenPresence.count = max(0, GameScreenPresence.count - 1)
        }
        // When "Next Level" swaps one game screen for another, the menu music must not start in between.
        if GameScreenPresence.count == 0 {
            UIApplication.shared.isIdleTimerDisabled = false
            container.audio.playMusic(.MENU)
        }
    }
}

/// How many game screens are on screen (two while one level cross-fades into the next).
@MainActor
private enum GameScreenPresence {
    static var count = 0
}

private struct GameContent: View {
    let vm: GameViewModel
    let onMap: () -> Void
    let onNextLevel: (Int) -> Void

    @Environment(AppContainer.self) private var container

    var body: some View {
        let levelNumber = vm.levelNumber
        let container = self.container
        let save = container.save.state
        let vm = self.vm
        let onMap = self.onMap
        let onNextLevel = self.onNextLevel
        let leave: () -> Void = {
            if let r = vm.result, r.unlockedNext { container.pendingPinHopFrom = levelNumber }
            onMap()
        }
        let next: () -> Void = {
            if vm.livesNow() > 0 { onNextLevel(levelNumber + 1) } else { vm.showNoLives() }
        }
        // iOS extras: leaving mid-level drops the autosave (the life rules stay Android's).
        let quit: () -> Void = {
            vm.extrasOnQuit()
            onMap()
        }
        let extras = container.save.extras
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Hud(vm: vm)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                BoardView(vm: vm)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if Features.boosters {
                    BoosterBar(vm: vm)
                }
                BottomBar(vm: vm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if Features.boosters {
                HammerSwingLayer(vm: vm)
                    .ignoresSafeArea()
            }

            EffectsLayer(vm: vm)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(GameScreen.rootSpace))
                } action: { r in
                    vm.screenOrigin = r.origin
                    vm.screenSize = r.size
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

            IntroBanner(vm: vm)
                .allowsHitTesting(false)

            Group {
                PauseDialog(
                    visible: vm.dialog == .PAUSE,
                    save: save,
                    onMusic: { container.save.setMusic($0) },
                    onSound: { container.save.setSfx($0) },
                    onVibration: { on in
                        container.save.setVibration(on)
                        if on { container.haptics.test() }
                    },
                    onResume: { vm.resume() },
                    onRestart: { if vm.leavingCostsLife { vm.askConfirmRestart() } else { vm.restart() } },
                    onMap: { if vm.leavingCostsLife { vm.askConfirmMap() } else { quit() } }
                )
                ConfirmDialog(
                    visible: vm.dialog == .CONFIRM_MAP,
                    title: "Leave level?",
                    message: "You'll lose a life if you leave now.",
                    yes: "Leave", no: "Stay", destructive: true,
                    onYes: {
                        vm.spendLifeForLeaving()
                        quit()
                    },
                    onNo: { vm.backToPause() }
                )
                ConfirmDialog(
                    visible: vm.dialog == .CONFIRM_RESTART,
                    title: "Restart?",
                    message: "You'll lose a life if you restart now.",
                    yes: "Restart", no: "Stay", destructive: true,
                    onYes: {
                        let before = vm.livesNow()
                        vm.spendLifeForLeaving()
                        if before - 1 <= 0 { vm.showNoLives() } else { vm.restart() }
                    },
                    onNo: { vm.backToPause() }
                )
                WinDialog(
                    visible: vm.dialog == .WIN,
                    levelNumber: levelNumber,
                    result: vm.result,
                    isLastLevel: levelNumber >= LevelCatalog.LEVEL_COUNT,
                    onNext: {
                        // iOS extras: the episode chest comes first.
                        if !vm.showChestIfDue(.NEXT) { next() }
                    },
                    onMap: { if !vm.showChestIfDue(.MAP) { leave() } },
                    coins: Features.economy ? vm.extras.winCoins : 0
                )
                LoseDialog(
                    visible: vm.dialog == .LOSE,
                    summary: vm.loseSummary,
                    livesLeft: vm.livesAfterLoss,
                    onRetry: { if vm.livesAfterLoss > 0 { vm.restart() } else { vm.showNoLives() } },
                    onMap: onMap,
                    onExtraMoves: { vm.grantExtraMoves(5) },
                    extraMoves: Features.boosters ? vm.extraMovesOffer(extras) : nil
                )
                NoLivesDialog(visible: vm.dialog == .NO_LIVES, save: save, onOk: leave)
                if Features.boosters {
                    BoosterShopDialog(
                        visible: vm.dialog == .BOOSTER_SHOP, booster: vm.extras.shop, coins: extras.coins,
                        onBuy: { vm.buyBooster($0) }, onClose: { vm.closeShop() }
                    )
                }
                if Features.episodeChest {
                    ChestDialog(visible: vm.dialog == .CHEST, reward: vm.extras.chest, onCollect: {
                        switch vm.finishChest() {
                        case .NEXT: next()
                        case .MAP: leave()
                        case nil: break
                        }
                    })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(.named(GameScreen.rootSpace))
    }
}

/// Full-screen particle layer (Kotlin: `Canvas(fillMaxSize) { vm.effects.draw(this) }`), in root coordinates.
private struct EffectsLayer: View {
    let vm: GameViewModel

    var body: some View {
        let frameTick = vm.frame
        let vm = self.vm
        Canvas { ctx, _ in
            _ = frameTick // capture the changing frame so SwiftUI redraws this Canvas every tick
            var c = ctx
            c.translateBy(x: -vm.screenOrigin.x, y: -vm.screenOrigin.y)
            vm.effects.draw(c)
        }
    }
}

// ---------------------------------------------------------------- HUD

private extension View {
    /// QA shortcut that only exists in debug builds.
    @ViewBuilder
    func debugLongPress(_ action: @escaping () -> Void) -> some View {
        #if DEBUG
        self.onLongPressGesture(perform: action)
        #else
        self
        #endif
    }
}

private struct HudCard<Content: View>: View {
    let fill: LinearGradient
    let border: Color
    let content: Content

    init(_ fill: LinearGradient, _ border: Color, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.border = border
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .circular)
        content
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: 4))
            .clipShape(shape)
            .background {
                // Modifier.shadow(8.dp, ambient/spot = 0x664A1C6E).
                shape.fill(border).shadow(color: Color(argb: 0x664A1C6E).opacity(0.3), radius: 5.5, x: 0, y: 4)
            }
    }
}

private func verticalGradient(_ colors: [Color]) -> LinearGradient {
    LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
}

private struct Hud: View {
    let vm: GameViewModel

    @Environment(\.palette) private var p

    var body: some View {
        let vm = self.vm
        HStack(spacing: 8) {
            // Moves
            let low = vm.movesLeft <= 5
            let movesFill = low
                ? verticalGradient([Color(argb: 0xFFFFD83A), Color(argb: 0xFFFF8A1F)])
                : verticalGradient([lighten(p.hudBar, 0.1), p.hudBar])
            let movesOutline = low ? Color(argb: 0xFF9A4100) : p.hudBarDark
            HudCard(movesFill, low ? Color(argb: 0xFFE0691A) : p.hudBarDark) {
                VStack(spacing: 0) {
                    OutlinedText("MOVES", fontSize: TypeScale.Caption, outline: movesOutline, outlineWidth: 2)
                    OutlinedText(String(vm.movesLeft), fontSize: 38, outline: movesOutline, outlineWidth: 2.5, maxLines: 1)
                }
            }
            .frame(width: 84)
            // iOS extras: +5 Moves punches the card (and sparkles at its centre).
            .keyframeAnimator(initialValue: CGFloat(1), trigger: vm.extras.movesPunch) { content, s in
                content.scaleEffect(s)
            } keyframes: { _ in
                MoveKeyframe(CGFloat(1.22))
                SpringKeyframe(CGFloat(1), spring: composeSpring(dampingRatio: 0.4, stiffness: 420))
            }
            .onGeometryChange(for: CGPoint.self) { proxy in
                let f = proxy.frame(in: .named(GameScreen.rootSpace))
                return CGPoint(x: f.midX, y: f.midY)
            } action: { c in
                vm.extras.movesCardCenter = c
            }
            .debugLongPress { vm.debugFinish(win: true) }

            // Goal
            HudCard(verticalGradient([p.panel, p.panelAlt]), p.cardBorder) {
                VStack(spacing: 0) {
                    OutlinedText(
                        vm.level.goal == .SCORE ? "TARGET" : "GOAL", fontSize: TypeScale.Caption, color: p.accent,
                        outline: shade(p.accent, 0.55), outlineWidth: 1.5, shadow: false
                    )
                    GoalSlots(vm: vm)
                }
            }
            .frame(maxWidth: .infinity)

            // Score
            HudCard(verticalGradient([lighten(p.hudBar, 0.1), p.hudBar]), p.hudBarDark) {
                VStack(spacing: 0) {
                    OutlinedText("SCORE", fontSize: TypeScale.Caption, outline: p.hudBarDark, outlineWidth: 2)
                    // animateIntAsState(score, tween(450))
                    ScoreText(value: Double(vm.score), outline: p.hudBarDark)
                        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45), value: vm.score)
                    Spacer().frame(height: 4)
                    StarBar(vm: vm)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                }
            }
            .frame(width: 112)
            .debugLongPress { vm.debugFinish(win: false) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
    }
}

/// The HUD score, counting towards the real score (Compose `animateIntAsState` truncates to Int).
private struct ScoreText: View, Animatable {
    var value: Double
    let outline: Color

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        OutlinedText(GoalTracker.formatNumber(Int(value)), fontSize: 22, outline: outline, outlineWidth: 2, maxLines: 1)
    }
}

private struct GoalSlots: View {
    let vm: GameViewModel

    @Environment(\.palette) private var p

    var body: some View {
        if vm.level.goal == .SCORE {
            OutlinedText(
                GoalTracker.formatNumber(vm.level.scoreTarget), fontSize: 26, color: p.text, outline: p.cardBorder,
                outlineWidth: 1.5, shadow: false, maxLines: 1
            )
        } else {
            let remaining = vm.goalRemaining
            let punch = vm.goalPunch
            HStack(alignment: .center, spacing: 10) {
                ForEach(remaining.indices, id: \.self) { i in
                    GoalSlot(vm: vm, index: i, remaining: remaining[i], bump: i < punch.count ? punch[i] : 0)
                }
            }
        }
    }
}

private struct GoalSlot: View {
    let vm: GameViewModel
    let index: Int
    let remaining: Int
    let bump: Int

    @Environment(\.palette) private var p
    @State private var punchSeq = 0

    var body: some View {
        let vm = self.vm
        let index = self.index
        let collect = vm.level.collect
        let color: CandyColor? = index < collect.count ? collect[index].color : nil
        HStack(alignment: .center, spacing: 0) {
            ZStack {
                GoalIcon(goal: vm.level.goal, color: color, size: 36)
                if remaining == 0 {
                    ZStack {
                        Circle().fill(p.success)
                        Circle().strokeBorder(Color.white, lineWidth: 2)
                        Icon(Icons.Check, contentDescription: nil, tint: .white)
                            .frame(width: 14, height: 14)
                    }
                    .frame(width: 20, height: 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(width: 40, height: 40)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: punchSeq) { content, s in
                content.scaleEffect(s)
            } keyframes: { _ in
                // punch.snapTo(1.35f); punch.animateTo(1f, spring(dampingRatio = 0.4f, stiffness = 500f))
                MoveKeyframe(CGFloat(1.35))
                SpringKeyframe(CGFloat(1), spring: composeSpring(dampingRatio: 0.4, stiffness: 500))
            }
            .onGeometryChange(for: CGPoint.self) { proxy in
                let f = proxy.frame(in: .named(GameScreen.rootSpace))
                return CGPoint(x: f.midX, y: f.midY)
            } action: { c in
                vm.goalSlotCenter[index] = c
            }
            if remaining > 0 {
                OutlinedText(String(remaining), fontSize: 22, color: p.text, outline: p.cardBorder, outlineWidth: 1.5, shadow: false)
            }
        }
        .onChange(of: bump) { _, b in
            if b > 0 { punchSeq &+= 1 }
        }
    }
}

private struct StarBar: View {
    let vm: GameViewModel

    @Environment(\.palette) private var p
    @State private var punchSeq = [0, 0, 0]

    var body: some View {
        let th = vm.starThresholds
        let maxScore = th[2].coerceAtLeast(1)
        let fillTarget = (Float(vm.score) / Float(maxScore)).coerceIn(0, 1)
        let lit = vm.starsLit
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Capsule(style: .circular).fill(srgbColor(RGBA(0, 0, 0, 0.3)))
                    Capsule(style: .circular)
                        .fill(verticalGradient([Color(argb: 0xFFFFF1A8), p.gold, Color(argb: 0xFFFF9E1B)]))
                        .frame(width: w * CGFloat(fillTarget))
                        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.4), value: fillTarget)
                }
                .frame(width: w, height: 10, alignment: .leading)
                .clipShape(Capsule(style: .circular))
                .overlay(Capsule(style: .circular).strokeBorder(srgbColor(RGBA(1, 1, 1, 0.3)), lineWidth: 1))
                ForEach(0..<3, id: \.self) { i in
                    let frac = (Float(th[i]) / Float(maxScore)).coerceIn(0.08, 1)
                    StarIcon(lit: i < lit, size: 20)
                        .keyframeAnimator(initialValue: CGFloat(1), trigger: punchSeq[i]) { content, s in
                            content.scaleEffect(s)
                        } keyframes: { _ in
                            // s.snapTo(1.6f); s.animateTo(1f, spring(dampingRatio = 0.4f, stiffness = 400f))
                            MoveKeyframe(CGFloat(1.6))
                            SpringKeyframe(CGFloat(1), spring: composeSpring(dampingRatio: 0.4, stiffness: 400))
                        }
                        .offset(x: (w - 20) * CGFloat(frac))
                }
            }
            .frame(width: w, height: geo.size.height, alignment: .leading)
        }
        .onChange(of: lit) { _, now in
            if now > 0 { punchSeq[(now - 1).coerceIn(0, 2)] &+= 1 }
        }
    }
}

// ---------------------------------------------------------------- bottom bar

private struct BottomBar: View {
    let vm: GameViewModel

    @Environment(\.palette) private var p

    var body: some View {
        let vm = self.vm
        ZStack {
            IconButton3D(Icons.Pause, onClick: { vm.pause() }, color: p.accent2, size: 54, contentDescription: "Pause")
                .frame(maxWidth: .infinity, alignment: .leading)
            GlassChip("Level \(vm.levelNumber)", fontSize: 20)
            OutlinedText(vm.episodeName, fontSize: TypeScale.Caption, outlineWidth: 2, lineHeight: 15)
                .frame(width: 96)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

// ---------------------------------------------------------------- intro banner

/// "Level N — goal" banner sliding in after the intro drop, timed on the game clock.
private struct IntroBanner: View {
    let vm: GameViewModel

    @Environment(\.palette) private var p

    var body: some View {
        // Kotlin: BoxWithConstraints(fillMaxSize) at the screen root, card centred, slid by translationX.
        let screen = CGRect(origin: vm.screenOrigin, size: vm.screenSize)
        let x = slideX(screen.width)
        if screen.width > 0 {
            IntroCard(levelNumber: vm.levelNumber, goalDescription: vm.goalDescription, color: p.accent2)
                .padding(.horizontal, 28)
                .frame(width: screen.width)
                .offset(x: x)
                .opacity(x == screen.width * 2 ? 0 : 1)
                .position(x: screen.midX, y: screen.midY)
        }
    }

    /// Reads the game frame only while the banner is on screen, so the view is idle the rest of the level.
    private func slideX(_ widthPx: CGFloat) -> CGFloat {
        let t = vm.time - vm.introBannerAt
        if t < 0 || t > 2.45 { return widthPx * 2 }
        _ = vm.frame
        if t < 0.45 { return widthPx * CGFloat(1 - Easing.outBack(t / 0.45, 1.2)) }
        if t < 2.05 { return 0 }
        return -widthPx * CGFloat(Easing.inQuad((t - 2.05) / 0.4))
    }
}

private struct IntroCard: View {
    let levelNumber: Int
    let goalDescription: String
    let color: Color

    var body: some View {
        CandyCard(color: color) {
            OutlinedText("Level \(levelNumber)", fontSize: TypeScale.Title, outline: shade(color, 0.5))
            OutlinedText(goalDescription, fontSize: TypeScale.Body, outline: shade(color, 0.5), outlineWidth: 2)
        }
    }
}
