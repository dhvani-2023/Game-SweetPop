import SwiftUI
import GameKit

/// Pin-hop state after a win that unlocked a new level (plain values read by the per-frame pin layer).
private final class PinHop {
    /// Kotlin `remember { container.pendingPinHopFrom.also { container.pendingPinHopFrom = null } }`.
    var from: Int?
    /// Kotlin `hopStart`: clock time the hop started, −1 before.
    var start: Double = -1

    init(from: Int?) {
        self.from = from
    }
}

/// The map screen: scrolling level map with the "you are here" pin, lives / stars chips, settings and Play.
/// iOS extras (Extras/Features.swift): coin pill + coin fly-in, Daily Spin button, login gift, "Continue level N?".
struct HomeScreen: View {
    let onPlay: (Int) -> Void
    let onSettings: () -> Void

    /// Coordinate space of the screen root (coin pill → coin fly-in target).
    static let space = "home"

    @Environment(\.palette) private var p
    @Environment(AppContainer.self) private var container
    @Environment(\.safeDrawingInsets) private var safe
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var startLevel: Int? = nil
    @State private var showLives = false
    @State private var showNoLives = false

    @State private var mapState = MapState()
    @State private var fx = Effects()
    /// Kotlin `withFrameNanos` loop: clock (dt ≤ 0.05 s), effects update and redraw every frame.
    @State private var loop = GameLoop()
    @State private var hop: PinHop? = nil
    @State private var nowStart = Date()

    // iOS extras.
    @State private var shower = CoinShower()
    @State private var coinBump = 0
    @State private var chipsWidth: CGFloat = 0
    @State private var showCoins = false
    @State private var showSpin = false
    @State private var loginDay: Int? = nil
    @State private var continueSnap: LevelSnapshot? = nil
    @State private var viewport: CGSize = .zero

    var body: some View {
        let save = container.save.state
        let current = save.highestUnlocked
        GeometryReader { geo in
            ZStack(alignment: .top) {
                LevelMap(
                    state: mapState,
                    save: save,
                    current: current,
                    onNodeTap: { n, c in
                        if n <= current {
                            startLevel = n
                        } else {
                            container.audio.play(.SWAP_BACK)
                            fx.banner("Locked!", Float(c.x), Float(c.y) - 40, 28)
                        }
                    }
                ) {
                    if let hop {
                        MapPinLayer(state: mapState, loop: loop, hop: hop, current: current, accent: p.accent)
                    }
                }

                // Effects overlay (screen space, like the Kotlin pin + effects canvas).
                FxLayer(fx: fx, loop: loop)

                topBar(save, width: geo.size.width)

                if Features.dailySpin {
                    // Re-checked every 30 s, so the "!" appears at midnight while the map is open.
                    TimelineView(.periodic(from: .now, by: 30)) { tl in
                        SpinButton(
                            available: DailySpin.isAvailable(spinDay: container.save.extras.spinDay, today: Days.epochDay(tl.date)),
                            onClick: { showSpin = true }
                        )
                    }
                    .padding(.top, safe.top + 78)
                    .padding(.leading, safe.leading + 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                bottomBar(current)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                if Features.economy {
                    CoinShowerLayer(shower: shower, loop: loop)
                }

                LevelStartDialog(
                    level: startLevel.map { LevelCatalog.get($0) },
                    starsEarned: startLevel.map { save.starsFor($0) } ?? 0,
                    best: startLevel.map { save.bestFor($0) } ?? 0,
                    onPlay: { n in
                        startLevel = nil
                        if save.livesNow().lives > 0 { onPlay(n) } else { showNoLives = true }
                    },
                    onClose: { startLevel = nil }
                )
                LivesInfoDialog(visible: showLives, save: save, onClose: { showLives = false })
                NoLivesDialog(visible: showNoLives, save: save, onOk: { showNoLives = false })

                if Features.economy {
                    CoinsInfoDialog(visible: showCoins, extras: container.save.extras, onClose: { showCoins = false })
                }
                if Features.dailySpin {
                    DailySpinDialog(visible: showSpin, onClose: { prize in
                        showSpin = false
                        celebrate(prize)
                    })
                }
                if Features.loginGift {
                    LoginGiftDialog(day: loginDay, onClaim: claimLoginGift)
                }
                if Features.autosave {
                    ContinueLevelDialog(
                        snapshot: continueSnap,
                        onContinue: {
                            guard let s = continueSnap else { return }
                            container.extras.pendingRestore = s
                            continueSnap = nil
                            onPlay(s.level)
                        },
                        onDiscard: {
                            AutoSave.clear()
                            continueSnap = nil
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(350))
                                checkLoginGift()
                            }
                        }
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(.named(HomeScreen.space))
            .onAppear {
                viewport = geo.size
                start(viewport: geo.size, current: current)
            }
            .onChange(of: geo.size) { _, s in viewport = s }
        }
        .ignoresSafeArea()
        .task(id: hop == nil) { await runPinHop() }
        .task { await runExtrasIntro() }
        .onChange(of: scenePhase) { _, phase in
            // A new day while the map stays open: the login gift on return.
            if phase == .active { checkLoginGift() }
        }
        .onDisappear { loop.stop() }
    }

    // ------------------------------------------------------------------ bars

    private func topBar(_ save: SaveData, width: CGFloat) -> some View {
        let ex: ExtrasData? = Features.economy ? container.save.extras : nil
        // With the coin pill the chips can outgrow narrow phones: scale them (stably) instead of truncating.
        let available = width - safe.leading - safe.trailing - 28 - 54 - 8
        let scale = ex == nil ? 1 : topBarChipScale(available: available, stars: save.totalStars, coins: ex?.coins, dynamicTypeSize: dynamicTypeSize)
        return HStack(spacing: 0) {
            HStack(spacing: 0) {
                // rememberNow(): the lives timer ticks every second.
                TimelineView(.periodic(from: nowStart, by: 1)) { tl in
                    let now = Int64(tl.date.timeIntervalSince1970 * 1000)
                    let lives = save.livesNow(now: now)
                    GlassChip(Lives.timerText(lives, now), onClick: { showLives = true }) {
                        HeartBadge(lives.lives)
                    }
                }
                Color.clear.frame(width: 8, height: 1)
                GlassChip(String(save.totalStars)) {
                    StarIcon(lit: true, size: 38)
                }
                if let ex {
                    Color.clear.frame(width: 8, height: 1)
                    CoinPill(coins: container.extras.shownCoins(ex.coins), bump: coinBump, onClick: { showCoins = true })
                        .onGeometryChange(for: CGPoint.self) { proxy in
                            let f = proxy.frame(in: .named(HomeScreen.space))
                            return CGPoint(x: f.minX + f.height / 2, y: f.midY)
                        } action: { c in
                            shower.target = c
                        }
                }
            }
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { chipsWidth = $0 }
            .scaleEffect(scale, anchor: .leading)
            .frame(width: scale < 1 ? chipsWidth * scale : nil, alignment: .leading)
            Spacer(minLength: 0)
            IconButton3D(Icons.Settings, onClick: onSettings, color: p.accent2, size: 54, contentDescription: "Settings")
        }
        // Kotlin windowInsetsPadding(safeDrawing) pads every side, then padding(14, 8, 14, 22).
        .padding(EdgeInsets(top: safe.top + 8, leading: safe.leading + 14, bottom: safe.bottom + 22, trailing: safe.trailing + 14))
        .frame(maxWidth: .infinity)
        .background(
            // A Compose background doesn't take touches: the map still scrolls under the shade.
            LinearGradient(
                colors: [srgbColor(RGBA(0, 0, 0, 0.45)), srgbColor(RGBA(0, 0, 0, 0.22)), RGBA.transparent.color],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
    }

    private func bottomBar(_ current: Int) -> some View {
        CandyButton3D(
            "Level \(current)", onClick: { startLevel = current },
            color: p.success, height: 72, fontSize: 32, icon: Icons.Play, breathing: true
        )
        .frame(minWidth: 230)
        .fixedSize()
        .frame(maxWidth: .infinity)
        // Kotlin windowInsetsPadding(safeDrawing) pads every side, then padding(top = 28, bottom = 14).
        .padding(EdgeInsets(top: safe.top + 28, leading: safe.leading, bottom: safe.bottom + 14, trailing: safe.trailing))
        .background(
            LinearGradient(colors: [RGBA.transparent.color, srgbColor(RGBA(0, 0, 0, 0.35))], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        )
    }

    // ------------------------------------------------------------------ effects

    private func start(viewport: CGSize, current: Int) {
        guard hop == nil else { return }
        let h = PinHop(from: container.pendingPinHopFrom)
        container.pendingPinHopFrom = nil
        hop = h

        // LaunchedEffect(Unit): menu music + lives refresh.
        container.audio.playMusic(.MENU)
        container.save.refreshLives()

        // Frame loop.
        let fx = self.fx
        let shower = self.shower
        loop.maxDelta = 0.05
        loop.onTick = { dt in
            fx.update(Float(dt))
            shower.update(Float(dt))
        }
        loop.start()
        if Features.economy { prepareCoinShower() }

        // Auto-scroll so the current level sits at ~40 % of the viewport.
        mapState.layout(width: viewport.width, height: viewport.height)
        let viewportH = viewport.height > 0 ? viewport.height : 1800 / BoardPainter.referenceDensity
        let below = max(0, Int((Float(viewportH) * 0.6 - Float(MAP_PADDING)) / Float(MAP_ROW)))
        let focus = h.from ?? current
        mapState.scrollToItem(max(0, focus - 1 - below))
    }

    // ------------------------------------------------------------------ iOS extras

    /// Coins landing in the pill: it counts up a share per coin and punches; sparkles when the last one lands.
    private func prepareCoinShower() {
        let session = container.extras
        let audio = container.audio
        let shower = self.shower
        let fx = self.fx
        var landed = 0
        shower.onArrive = { value, last in
            session.coinsInFlight = max(0, session.coinsInFlight - value)
            coinBump &+= 1
            landed += 1
            audio.play(.CLICK, rate: min(2, 1.45 + 0.05 * Float(landed)), volume: 0.55)
            if landed % 2 == 0 { Haptics.shared.light() }
            if last {
                landed = 0
                audio.play(.STAR, rate: 1.3, volume: 0.6)
                fx.sparkles(Float(shower.target.x), Float(shower.target.y), 8, 26, 12, Color(argb: 0xFFFFF4B0))
            }
        }
    }

    /// Flies [amount] coins from the middle of the screen into the pill; returns the flight time.
    @discardableResult
    private func launchCoins(_ amount: Int) -> Double {
        guard Features.economy, amount > 0, viewport.width > 0 else { return 0 }
        return shower.launch(amount: amount, from: CGPoint(x: viewport.width / 2, y: viewport.height * 0.5))
    }

    /// On arrival: coins earned elsewhere fly in, then "Continue level N?" (autosave) or the login gift.
    private func runExtrasIntro() async {
        try? await Task.sleep(for: .milliseconds(500))
        if Task.isCancelled { return }
        if Features.economy && container.extras.coinsInFlight > 0 {
            let d = launchCoins(container.extras.coinsInFlight)
            try? await Task.sleep(for: .milliseconds(Int(d * 1000) + 250))
            if Task.isCancelled { return }
        }
        if Features.autosave, let snap = AutoSave.load(), snap.level <= container.save.state.highestUnlocked {
            continueSnap = snap
            return
        }
        checkLoginGift()
    }

    /// First map visit of a new day: the 7-day login gift.
    private func checkLoginGift() {
        guard Features.loginGift, loginDay == nil, continueSnap == nil, !showSpin else { return }
        let ex = container.save.extras
        loginDay = LoginGift.dayToClaim(lastDay: ex.loginDay, lastStreak: ex.loginStreak, today: Days.epochDay())
    }

    private func claimLoginGift(_ day: Int) {
        guard loginDay != nil else { return }
        container.save.claimLoginGift(day: day, today: Days.epochDay())
        let coins = LoginGift.coins(day: day)
        if Features.economy { container.extras.coinsInFlight += coins }
        loginDay = nil
        container.audio.play(.UNLOCK)
        Haptics.shared.medium()
        if LoginGift.boostersPerKind(day: day) > 0 {
            fx.banner("+1 of each booster!", Float(viewport.width / 2), Float(viewport.height * 0.42), 30, Color(argb: 0xFFB8FFCF))
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            launchCoins(coins)
        }
    }

    /// Daily Spin closed after a win: coins fly in, other prizes get a banner.
    private func celebrate(_ prize: DailySpin.Prize?) {
        guard let prize else { return }
        let cx = Float(viewport.width / 2)
        let cy = Float(viewport.height * 0.42)
        switch prize {
        case .coins(let n):
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                launchCoins(n)
            }
        case .booster(let b):
            fx.banner("+1 \(b.shortName)!", cx, cy, 32, Color(argb: 0xFFB8FFCF))
        case .life:
            fx.banner("+1 Life!", cx, cy, 32, Color(argb: 0xFFFFB3C1))
        }
    }

    /// Kotlin: delay(550) → hop starts (whoosh) → delay(900) → unlock sound + sparkles on the new node.
    private func runPinHop() async {
        guard let hop, let from = hop.from else { return }
        try? await Task.sleep(nanoseconds: 550_000_000)
        if Task.isCancelled { return }
        hop.start = loop.time
        container.audio.play(.WHOOSH, volume: 0.6)
        try? await Task.sleep(nanoseconds: 900_000_000)
        if Task.isCancelled { return }
        container.audio.play(.UNLOCK)
        let c = mapState.screenCenter(from + 1)
        fx.sparkles(Float(c.x), Float(c.y), 12, 40, 14, Color(argb: 0xFFFFF4B0))
    }
}

/// The pin, drawn in map content coordinates so it scrolls with the nodes. Redraws every frame.
private struct MapPinLayer: View {
    let state: MapState
    let loop: GameLoop
    let hop: PinHop
    let current: Int
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let box: CGFloat = 120

    var body: some View {
        let frameTick = loop.frame
        let t = Float(loop.time)
        // The idle bob / squash is decorative (still with Reduce Motion); the hop itself always plays.
        let ambient: Float = reduceMotion || GameKit.Motion.reduce ? 0 : t
        if let pos = pinPosition(t, ambient) {
            Canvas { ctx, size in
                _ = frameTick // capture the changing frame so SwiftUI redraws this Canvas every tick
                ctx.drawMapPin(CGPoint(x: size.width / 2, y: size.height / 2), ambient, accent)
            }
            .frame(width: Self.box, height: Self.box)
            .offset(x: pos.x - Self.box / 2, y: pos.y - Self.box / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func pinPosition(_ t: Float, _ ambient: Float) -> CGPoint? {
        guard state.visibleRange.contains(current) else { return nil }
        let target = state.nodeCenter(current)
        let lift = (NODE_SIZE * 1.15 / 2 + 24)
        if let from = hop.from, hop.start < 0 || Double(t) - hop.start < 0.9 {
            let k = hop.start < 0 ? 0 : Float((Double(t) - hop.start) / 0.9).coerceIn(0, 1)
            let pos = pinHopPosition(state.nodeCenter(from), target, k)
            return CGPoint(x: pos.x, y: pos.y - lift)
        }
        let bob = CGFloat(Kt.sin(ambient * 2.2) * 4)
        return CGPoint(x: target.x, y: target.y - lift + bob)
    }
}

private let NODE_SIZE: CGFloat = 64

/// Screen-space effects ("Locked!", unlock sparkles) driven by the Home frame loop.
private struct FxLayer: View {
    let fx: Effects
    let loop: GameLoop

    var body: some View {
        let frameTick = loop.frame
        let fx = self.fx
        Canvas { ctx, _ in _ = frameTick; fx.draw(ctx) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
