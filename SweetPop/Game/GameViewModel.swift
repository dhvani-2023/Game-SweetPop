import SwiftUI
import Observation
import GameKit

enum GamePhase { case INTRO, PLAYING, FRENZY, WON, LOST }

/// BOOSTER_SHOP and CHEST belong to the iOS extras (Extras/Features.swift).
enum GameDialog { case NONE, PAUSE, WIN, LOSE, NO_LIVES, CONFIRM_MAP, CONFIRM_RESTART, BOOSTER_SHOP, CHEST }

struct GameResult: Equatable {
    let stars: Int
    let score: Int
    let newBest: Bool
    let unlockedNext: Bool
}

extension GameResult {
    /// Kotlin `GameResult(stars, score, newBest, unlockedNext)`.
    init(_ stars: Int, _ score: Int, _ newBest: Bool, _ unlockedNext: Bool) {
        self.init(stars: stars, score: score, newBest: newBest, unlockedNext: unlockedNext)
    }
}

/**
 * Runs one level: owns the board, the rules engine and the goal tracker, and plays every turn as a
 * task that waits on the game clock. The clock only advances in [tick] (driven by the screen's
 * frame loop) and stops while paused, so logic and animations freeze together.
 *
 * iOS: the frame loop is GameKit `GameLoop` (CADisplayLink, 120 Hz), owned here as [loop]; the screen
 * starts it on appear and calls [onCleared] when it goes away. Kotlin coroutines → Swift tasks on the main
 * actor; `wait` suspends on a continuation that [tick] resumes, so pausing freezes every turn mid-flight.
 * Layout values (board origin, goal slots, screen size) are in points in the screen's root coordinate space.
 */
@MainActor
@Observable
final class GameViewModel {
    // Members without `private` below are used by the iOS extras (Extras/GameViewModel+Extras.swift).
    @ObservationIgnored let container: AppContainer
    var audio: AudioManager { container.audio }
    var haptics: Haptics { container.haptics }
    var save: SaveRepository { container.save }
    /// Kotlin `java.util.Random()` (unseeded).
    @ObservationIgnored private let rnd = JavaRandom(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds) ^ 0x5DEE_CE66_D)

    let levelNumber: Int
    let level: Level
    let episodeName: String
    let goalDescription: String

    @ObservationIgnored private(set) var board: Board!
    @ObservationIgnored private(set) var engine: BoardEngine!
    @ObservationIgnored private(set) var tracker: GoalTracker!
    let visuals = BoardVisuals()
    let effects = Effects()
    /// iOS extras state of this attempt (boosters, coins, chest, autosave).
    let extras = GameExtras()

    /// The frame loop that drives [tick] (Kotlin: the screen's `withFrameNanos` loop).
    let loop = GameLoop()

    /// Game clock in seconds (excludes paused time). Not observed: views redraw from [frame].
    @ObservationIgnored private(set) var time: Float = 0

    /// Incremented every tick; draw code reads it to redraw each frame.
    private(set) var frame: Int = 0

    private(set) var phase: GamePhase = .INTRO
    var dialog: GameDialog = .NONE
    private(set) var paused = false
    var movesLeft: Int
    private(set) var score = 0
    private(set) var starsLit = 0
    private(set) var introBannerAt: Float = -100
    private(set) var result: GameResult?
    private(set) var livesAfterLoss = 0
    private(set) var loseSummary = ""

    /// Remaining count shown in each HUD goal slot (collect counts update when the candy arrives).
    private(set) var goalRemaining: [Int] = []

    /// Bumped when a goal slot receives a candy, so the HUD can punch it.
    private(set) var goalPunch: [Int] = []

    /// Score thresholds for the three HUD star markers.
    let starThresholds: [Int]

    @ObservationIgnored private(set) var movesMade = 0

    // Layout, reported by the views (points, in the game screen's root coordinate space).
    @ObservationIgnored var boardOrigin: CGPoint = .zero
    @ObservationIgnored var cellPx: Float = 0
    @ObservationIgnored var screenSize: CGSize = .zero
    /// Top-left of the full screen in the root space (iOS: the root follows the safe area, the screen does not).
    @ObservationIgnored var screenOrigin: CGPoint = .zero
    @ObservationIgnored var goalSlotCenter: [Int: CGPoint] = [:]

    @ObservationIgnored private var nextId = 1
    @ObservationIgnored private var turnTask: Task<Void, Never>?
    @ObservationIgnored private var turnSeq = 0
    @ObservationIgnored var lastInteraction: Float = 0
    @ObservationIgnored private var waiters: [Waiter] = []
    @ObservationIgnored private var dueWaiters: [Waiter] = []

    private struct Waiter {
        let at: Float
        let cont: CheckedContinuation<Void, Never>
    }

    static let PRAISE = ["Yummy!", "Tasty!", "Sugar Rush!", "Pop-tastic!", "Sweet Pop!"]

    init(container: AppContainer, levelNumber: Int) {
        self.container = container
        self.levelNumber = levelNumber
        let level = LevelCatalog.get(levelNumber)
        self.level = level
        episodeName = LevelCatalog.episodeNameForLevel(levelNumber)
        goalDescription = GoalTracker.goalDescription(level)
        movesLeft = level.moves
        if level.goal == .SCORE {
            starThresholds = level.starScores
        } else {
            starThresholds = [max(1, level.starScores[1] / 2), level.starScores[1], level.starScores[2]]
        }
        waiters.reserveCapacity(4)
        dueWaiters.reserveCapacity(4)
        loop.maxDelta = 0.05
        loop.onTick = { [weak self] dt in self?.tick(Float(dt)) }
        setupBoard()
        // iOS autosave: "Continue level N?" hands the saved level over through the container.
        if Features.autosave, let snap = container.extras.takeRestore(for: levelNumber), snap.fits(level) {
            restoreBoard(snap)
        }
        startIntro()
    }

    private func setupBoard() {
        nextId = 1
        board = Board.fromLevel(level) {
            let id = nextId
            nextId += 1
            return id
        }
        engine = BoardEngine(board, level.colors, JavaRandom(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)), startId: nextId)
        tracker = GoalTracker(level)
        tracker.refresh(board)
        visuals.clear()
        effects.clear()
        movesLeft = tracker.movesLeft
        score = 0
        starsLit = 0
        movesMade = 0
        result = nil
        var remaining = [Int]()
        var punch = [Int]()
        switch level.goal {
        case .COLLECT:
            for t in level.collect {
                remaining.append(t.count)
                punch.append(0)
            }
        case .JELLY:
            remaining.append(tracker.jellyLeft)
            punch.append(0)
        case .FROSTING:
            remaining.append(tracker.frostingLeft)
            punch.append(0)
        case .SCORE:
            break
        }
        goalRemaining = remaining
        goalPunch = punch
    }

    /// iOS autosave (Extras/AutoSave.swift): rebuilds a saved level in progress exactly — cells, specials, jelly,
    /// frosting, score, moves, goals and stars. The refill RNG gets a new seed.
    private func restoreBoard(_ s: LevelSnapshot) {
        nextId = 1
        board = s.makeBoard(level) {
            let id = nextId
            nextId += 1
            return id
        }
        engine = BoardEngine(board, level.colors, JavaRandom(Int64(bitPattern: DispatchTime.now().uptimeNanoseconds)), startId: nextId)
        tracker = GoalTracker(level)
        s.apply(to: tracker)
        tracker.refresh(board)
        visuals.clear()
        effects.clear()
        movesLeft = tracker.movesLeft
        score = tracker.score
        starsLit = starThresholds.reduce(0) { $0 + (score >= $1 ? 1 : 0) }
        movesMade = s.movesMade
        result = nil
        switch level.goal {
        case .COLLECT: goalRemaining = tracker.collectRemaining
        case .JELLY: goalRemaining = [tracker.jellyLeft]
        case .FROSTING: goalRemaining = [tracker.frostingLeft]
        case .SCORE: goalRemaining = []
        }
        goalPunch = [Int](repeating: 0, count: goalRemaining.count)
        extras.restored(s)
    }

    // ------------------------------------------------------------------ clock

    func tick(_ dtSeconds: Float) {
        if paused { return }
        let dt = dtSeconds.coerceIn(0, 0.05)
        time += dt
        effects.update(dt)
        if !waiters.isEmpty {
            let now = time
            if waiters.contains(where: { $0.at <= now }) {
                var keep = 0
                for i in waiters.indices {
                    let w = waiters[i]
                    if w.at <= now {
                        dueWaiters.append(w)
                    } else {
                        waiters[keep] = w
                        keep += 1
                    }
                }
                waiters.removeLast(waiters.count - keep)
                for w in dueWaiters { w.cont.resume() }
                dueWaiters.removeAll(keepingCapacity: true)
            }
        }
        visuals.prune(time)
        maybeHint()
        frame &+= 1
    }

    /// Suspends the current turn for [seconds] of game time. Throws once the turn was cancelled (restart / leave).
    func wait(_ seconds: Float) async throws {
        if seconds <= 0 { return }
        try Task.checkCancellation()
        let target = time + seconds
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiters.append(Waiter(at: target, cont: c))
        }
        try Task.checkCancellation()
    }

    var busy: Bool { turnTask != nil }

    func startTurn(_ block: @escaping @MainActor () async throws -> Void) {
        if busy { return }
        launchTurn(block)
    }

    private func launchTurn(_ block: @escaping @MainActor () async throws -> Void) {
        turnSeq &+= 1
        let seq = turnSeq
        turnTask = Task { @MainActor [weak self] in
            if !Task.isCancelled {
                do { try await block() } catch {}
            }
            if let self, self.turnSeq == seq {
                self.turnTask = nil
                self.extrasTurnEnded()
            }
        }
    }

    /// Kotlin `turnJob?.cancel()` + `waiters.clear()`: the suspended turn wakes up cancelled and unwinds.
    private func cancelTurn() {
        turnSeq &+= 1
        turnTask?.cancel()
        turnTask = nil
        let pending = waiters
        waiters.removeAll()
        for w in pending { w.cont.resume() }
    }

    // ------------------------------------------------------------------ geometry

    func cellCenter(_ x: Float, _ y: Float) -> SIMD2<Float> {
        SIMD2(
            Float(boardOrigin.x) + (x + 0.5) * cellPx,
            Float(boardOrigin.y) + (Float(level.height - 1) - y + 0.5) * cellPx
        )
    }

    func center(_ p: Pos) -> SIMD2<Float> { cellCenter(Float(p.x), Float(p.y)) }

    var screenCenter: SIMD2<Float> {
        SIMD2(Float(screenOrigin.x) + Float(screenSize.width) / 2, Float(screenOrigin.y) + Float(screenSize.height) * 0.45)
    }

    /// Android pixel offsets were tuned at density 2.75 (the reference `Effects.k` uses); scale them to canvas units.
    var px: Float { effects.density / 2.75 }

    // ------------------------------------------------------------------ input

    var acceptsInput: Bool {
        phase == .PLAYING && !paused && dialog == .NONE && !busy && tracker.movesLeft > 0
    }

    func onTouch() {
        lastInteraction = time
        visuals.hint = nil
    }

    func onSwipe(_ from: Pos, _ dx: Int, _ dy: Int) {
        onTouch()
        if !acceptsInput { return }
        let to = Pos(from.x + dx, from.y + dy)
        if !engine.canSwap(from, to) { return }
        visuals.selected = nil
        if extrasSwap(from, to) { return } // Free Swap / Lollipop Hammer armed
        startTurn { try await self.performSwap(from, to) }
    }

    func onTap(_ p: Pos) {
        onTouch()
        if !acceptsInput { return }
        if extrasTap(p) { return } // Lollipop Hammer armed
        if board.candyAt(p) == nil {
            visuals.selected = nil
            return
        }
        if let sel = visuals.selected {
            if sel == p {
                visuals.selected = nil
            } else if sel.isAdjacent(p) && engine.canSwap(sel, p) {
                visuals.selected = nil
                if extrasSwap(sel, p) { return } // Free Swap armed
                startTurn { try await self.performSwap(sel, p) }
            } else {
                select(p)
            }
        } else {
            select(p)
        }
    }

    private func select(_ p: Pos) {
        visuals.selected = p
        visuals.selectedAt = time
        haptics.light()
    }

    private func maybeHint() {
        if phase != .PLAYING || busy || dialog != .NONE || visuals.hint != nil { return }
        if extras.armed != nil { return } // iOS extras: no swap hint while a booster waits for its target
        if time - lastInteraction < 5 { return }
        if !save.state.hints { return }
        let moves = MatchFinder.allValidMoves(board)
        if moves.isEmpty {
            lastInteraction = time
            return
        }
        visuals.hint = moves[rnd.nextInt(moves.count)]
        visuals.hintAt = time
    }

    // ------------------------------------------------------------------ intro

    private func startIntro() {
        phase = .INTRO
        // Kotlin launches on Main.immediate, so the drop motions exist before the first frame is drawn.
        let t0 = time + 0.15
        var maxDelay: Float = 0
        board.forEachCell { x, y, c in
            guard let candy = c.candy else { return }
            let delay = Float(x) * 0.035 + Float(y) * 0.03
            maxDelay = max(maxDelay, delay)
            visuals.motions[candy.id] = Motion(Float(x), Float(y + level.height) + 1, Float(x), Float(y), t0 + delay, 0.55, .OUT_BOUNCE)
        }
        launchTurn {
            try await self.wait(0.15 + maxDelay + 0.55)
            self.audio.play(.LAND, volume: 0.6)
            self.audio.play(.WHOOSH, volume: 0.5)
            self.introBannerAt = self.time
            try await self.wait(0.45 + 1.6 + 0.4)
            self.phase = .PLAYING
            self.lastInteraction = self.time
            if MatchFinder.findValidMove(self.board) == nil { try await self.shuffleBoard() }
        }
    }

    // ------------------------------------------------------------------ turn

    private func performSwap(_ a: Pos, _ b: Pos) async throws {
        guard let ca = board.candyAt(a), let cb = board.candyAt(b) else { return }
        audio.play(.SWAP, volume: 0.8)
        haptics.light()
        engine.swap(a, b)
        visuals.motions[ca.id] = Motion(Float(a.x), Float(a.y), Float(b.x), Float(b.y), time, 0.2, .IN_OUT)
        visuals.motions[cb.id] = Motion(Float(b.x), Float(b.y), Float(a.x), Float(a.y), time, 0.2, .IN_OUT)
        try await wait(0.2)
        if engine.isComboSwap(a, b) {
            useMove()
            try await runCombo(a, b)
            try await cascadeLoop(nil, 1)
        } else {
            let groups = MatchFinder.findGroups(board, swappedInto: b, other: a)
            if groups.isEmpty {
                engine.swap(a, b)
                visuals.motions[ca.id] = Motion(Float(b.x), Float(b.y), Float(a.x), Float(a.y), time, 0.2, .IN_OUT)
                visuals.motions[cb.id] = Motion(Float(a.x), Float(a.y), Float(b.x), Float(b.y), time, 0.2, .IN_OUT)
                audio.play(.SWAP_BACK, volume: 0.6)
                try await wait(0.2)
                return
            }
            useMove()
            try await cascadeLoop(groups, 0)
        }
        try await settle()
    }

    private func useMove() {
        tracker.useMove()
        movesLeft = tracker.movesLeft
        movesMade += 1
        if movesLeft == 5 && !tracker.isGoalComplete {
            effects.banner("5 moves left!", screenCenter.x, screenCenter.y, 34, Color(argb: 0xFFFFE27A))
        }
    }

    func cascadeLoop(_ initial: [MatchGroup]?, _ startCascade: Int) async throws {
        var cascade = startCascade
        var groups = initial ?? MatchFinder.findGroups(board)
        while !groups.isEmpty {
            if (2...6).contains(cascade) {
                effects.praise(Self.PRAISE[cascade - 2], screenCenter.x, screenCenter.y)
                haptics.medium()
            }
            audio.playChime(cascade)
            engine.beginMatches(groups, cascade)
            try await runWaves()
            try await spawnCreated()
            try await gravity()
            cascade += 1
            groups = MatchFinder.findGroups(board)
        }
    }

    func runWaves() async throws {
        while true {
            guard let w = engine.nextWave() else { break }
            presentWave(w)
            if engine.hasNextWave {
                try await wait(0.15)
            } else {
                try await wait(0.22)
                break
            }
        }
    }

    func spawnCreated() async throws {
        let created = engine.finishResolve()
        if created.isEmpty { return }
        audio.play(.SPECIAL, volume: 0.7)
        for it in created {
            visuals.grow[it.candy.id] = time
            let c = center(it.pos)
            effects.sparkles(c.x, c.y, 6, cellPx * 0.5, cellPx * 0.28)
        }
        try await wait(0.12)
    }

    private func presentWave(_ w: Wave) {
        if !w.cleared.isEmpty { audio.play(.POP, rate: 0.95 + rnd.nextFloat() * 0.15, volume: 0.75) }
        for cc in w.cleared {
            visuals.pops.append(PopAnim(cc.candy.color, cc.candy.special, cc.pos.x, cc.pos.y, time))
            let c = center(cc.pos)
            effects.burst(c.x, c.y, glowColor(cc.candy.color), cellPx)
            let slot = tracker.collectSlotFor(cc.candy.color)
            if slot >= 0 {
                tracker.collect(slot)
                if let target = goalSlotCenter[slot] {
                    effects.flyCandy(cc.candy.color, .NONE, c.x, c.y, Float(target.x), Float(target.y), cellPx) { [weak self] in
                        self?.onCollectArrive(slot)
                    }
                } else {
                    onCollectArrive(slot)
                }
            }
        }
        if !w.jellyHits.isEmpty {
            audio.play(.JELLY, volume: 0.6)
            for j in w.jellyHits {
                visuals.jellyPops.append(JellyPopAnim(j.pos.x, j.pos.y, j.layersBefore, time))
                let c = center(j.pos)
                effects.sparkles(c.x, c.y, 2, cellPx * 0.3, cellPx * 0.2, Color(argb: 0xFFFFC2E8))
            }
        }
        if !w.frostingHits.isEmpty {
            audio.play(.FROSTING, volume: 0.8)
            haptics.light()
            for f in w.frostingHits {
                visuals.frostHits[f.pos.x + f.pos.y * level.width] = time
                let c = center(f.pos)
                effects.crumbs(c.x, c.y, cellPx, pink: f.hpAfter >= 1)
            }
        }
        for t in w.triggers { presentTrigger(t) }
        for s in w.scores {
            addScore(s.points)
            let c = cellCenter(s.x, s.y)
            effects.floatScore(s.points, c.x, c.y, glowColor(s.color))
        }
        tracker.refresh(board)
        refreshObstacleGoals()
    }

    private func presentTrigger(_ t: Trigger) {
        let c = center(t.pos)
        let color = glowColor(t.color)
        switch t.special {
        case .STRIPED_H:
            rowBeam(t.pos.y, c, color)
            audio.play(.STRIPED, volume: 0.8)
            haptics.medium()
        case .STRIPED_V:
            columnBeam(t.pos.x, c, color)
            audio.play(.STRIPED, volume: 0.8)
            haptics.medium()
        case .WRAPPED:
            effects.shockwave(c.x, c.y, cellPx * 2.3, color)
            effects.shake(14 * effects.density / 2.75)
            audio.play(.WRAPPED)
            haptics.heavy()
        case .COLOR_BOMB:
            for p in t.area {
                let e = center(p)
                effects.zap(c.x, c.y, e.x, e.y)
            }
            audio.play(.COLOR_BOMB, volume: 0.8)
            haptics.heavy()
        case .NONE:
            break
        }
    }

    private func rowBeam(_ y: Int, _ origin: SIMD2<Float>, _ color: Color) {
        let left = Float(boardOrigin.x) + cellPx * 0.3
        let right = Float(boardOrigin.x) + Float(level.width) * cellPx - cellPx * 0.3
        let cy = cellCenter(0, Float(y)).y
        effects.beam(left, cy, right, cy, origin.x, cy, cellPx, color)
    }

    private func columnBeam(_ x: Int, _ origin: SIMD2<Float>, _ color: Color) {
        let top = Float(boardOrigin.y) + cellPx * 0.3
        let bottom = Float(boardOrigin.y) + Float(level.height) * cellPx - cellPx * 0.3
        let cx = cellCenter(Float(x), 0).x
        effects.beam(cx, top, cx, bottom, cx, origin.y, cellPx, color)
    }

    func runCombo(_ from: Pos, _ into: Pos) async throws {
        let start = engine.beginCombo(from, into)
        if let title = start.title { effects.praise(title, screenCenter.x, screenCenter.y) }
        haptics.heavy()
        let c = center(into)
        let glow = glowColor(start.color)
        switch start.kind {
        case .BOMB_BOMB:
            audio.play(.COLOR_BOMB)
            audio.play(.WRAPPED)
            effects.shockwave(c.x, c.y, cellPx * Float(max(level.width, level.height)), Color(argb: 0xFFFFE27A))
            effects.shake(22 * effects.density / 2.75)
            try await wait(0.25)
        case .BOMB_NORMAL:
            audio.play(.COLOR_BOMB)
            let b = center(start.bombPos ?? into)
            for p in start.area {
                let e = center(p)
                effects.zap(b.x, b.y, e.x, e.y)
            }
            try await wait(0.25)
        case .BOMB_STRIPED, .BOMB_WRAPPED:
            audio.play(.COLOR_BOMB)
            let b = center(start.bombPos ?? into)
            for p in start.converted {
                let e = center(p)
                effects.zap(b.x, b.y, e.x, e.y)
                if let k = board.candyAt(p) { visuals.pulses[k.id] = time }
                effects.sparkles(e.x, e.y, 2, cellPx * 0.3, cellPx * 0.25)
            }
            try await wait(0.3)
            audio.play(.SPECIAL, volume: 0.7)
            try await wait(0.25)
        case .STRIPED_STRIPED:
            rowBeam(into.y, c, glow)
            columnBeam(into.x, c, glow)
            audio.play(.STRIPED)
        case .STRIPED_WRAPPED:
            for d in -1...1 {
                if (0..<level.height).contains(into.y + d) { rowBeam(into.y + d, c, glow) }
                if (0..<level.width).contains(into.x + d) { columnBeam(into.x + d, c, glow) }
            }
            audio.play(.STRIPED)
            audio.play(.WRAPPED, volume: 0.7)
            effects.shake(16 * effects.density / 2.75)
        case .WRAPPED_WRAPPED:
            effects.shockwave(c.x, c.y, cellPx * 3.6, glow)
            effects.shake(22 * effects.density / 2.75)
            audio.play(.WRAPPED)
        }
        try await runWaves()
        try await spawnCreated()
        try await gravity()
    }

    func gravity() async throws {
        let moves = engine.applyGravity()
        if moves.isEmpty { return }
        var longest: Float = 0
        for m in moves {
            let dur = 0.10 + 0.10 * Kt.sqrt(m.distance)
            visuals.motions[m.candy.id] = Motion(m.fromX, m.fromY, Float(m.toX), Float(m.toY), time, dur, .IN, squash: true)
            longest = max(longest, dur)
        }
        try await wait(longest)
        audio.play(.LAND, volume: 0.5)
    }

    func settle() async throws {
        tracker.refresh(board)
        refreshObstacleGoals()
        if try await checkEnd() { return }
        if MatchFinder.findValidMove(board) == nil { try await shuffleBoard() }
    }

    private func shuffleBoard() async throws {
        for _ in 0..<3 {
            effects.banner("Shuffle!", screenCenter.x, screenCenter.y)
            audio.play(.WHOOSH)
            try await wait(0.6)
            let moves = engine.shuffle()
            for m in moves {
                visuals.motions[m.candy.id] = Motion(m.fromX, m.fromY, Float(m.toX), Float(m.toY), time, 0.45, .IN_OUT)
            }
            try await wait(0.5)
            try await cascadeLoop(nil, 0)
            if MatchFinder.findValidMove(board) != nil { return }
        }
    }

    private func checkEnd() async throws -> Bool {
        if level.goal != .SCORE && tracker.isGoalComplete {
            try await win()
            return true
        }
        if tracker.movesLeft <= 0 {
            if level.goal == .SCORE && tracker.isGoalComplete { try await win() } else { try await lose() }
            return true
        }
        return false
    }

    // ------------------------------------------------------------------ score & goals

    private func addScore(_ points: Int) {
        tracker.addScore(points)
        score = tracker.score
        let lit = starThresholds.reduce(0) { $0 + (score >= $1 ? 1 : 0) }
        if lit > starsLit {
            for i in starsLit..<lit { audio.play(.STAR, rate: 1 + 0.12 * Float(i), volume: 0.7) }
            starsLit = lit
        }
        if tracker.consumeTargetReached() {
            // Kotlin: 120 raw pixels above the centre.
            effects.banner("Target Reached!", screenCenter.x, screenCenter.y - 120 * px, 34, Color(argb: 0xFFB8FFCF))
        }
    }

    private func refreshObstacleGoals() {
        switch level.goal {
        case .JELLY: if !goalRemaining.isEmpty { goalRemaining[0] = tracker.jellyLeft }
        case .FROSTING: if !goalRemaining.isEmpty { goalRemaining[0] = tracker.frostingLeft }
        default: break
        }
    }

    private func onCollectArrive(_ slot: Int) {
        if !goalRemaining.indices.contains(slot) { return }
        goalRemaining[slot] = (goalRemaining[slot] - 1).coerceAtLeast(0)
        goalPunch[slot] = goalPunch[slot] + 1
    }

    // ------------------------------------------------------------------ win / lose

    private func win() async throws {
        phase = .FRENZY
        let frenzyMoves = tracker.movesLeft // iOS extras: +2 coins per move left when Sweet Frenzy starts
        extrasFrenzyStarted()
        visuals.hint = nil
        try await wait(0.35)
        effects.praise("Sweet Frenzy!", screenCenter.x, screenCenter.y)
        audio.play(.SPECIAL)
        haptics.medium()
        try await wait(0.9)
        var converted = 0
        while tracker.movesLeft > 0 {
            tracker.useMove()
            movesLeft = tracker.movesLeft
            addScore(600)
            if converted < 15 {
                let candidates = board.positions().filter {
                    guard let k = board.candyAt($0) else { return false }
                    return k.special == .NONE && k.color != .NONE
                }
                if !candidates.isEmpty {
                    let p = candidates[rnd.nextInt(candidates.count)]
                    let k = board.candyAt(p)!
                    k.special = rnd.nextBoolean() ? .STRIPED_H : .STRIPED_V
                    visuals.pulses[k.id] = time
                    let c = center(p)
                    effects.sparkles(c.x, c.y, 4, cellPx * 0.4, cellPx * 0.25)
                    effects.floatScore(600, c.x, c.y, Color(argb: 0xFFFFE27A))
                    audio.play(.SWAP, rate: 1 + Float(converted) * 0.04, volume: 0.6)
                }
                converted += 1
                try await wait(0.11)
            }
        }
        try await wait(0.3)
        for _ in 0..<6 {
            if !engine.beginFireAll() { break }
            try await runWaves()
            try await spawnCreated()
            try await gravity()
            try await cascadeLoop(nil, 1)
        }
        phase = .WON
        let stars = tracker.starsFor(tracker.score)
        let saved = save.state
        let best = saved.bestFor(levelNumber)
        let unlocks = saved.highestUnlocked == levelNumber && levelNumber < LevelCatalog.LEVEL_COUNT
        result = GameResult(stars, tracker.score, tracker.score > best, unlocks)
        save.recordWin(levelNumber, stars, tracker.score)
        extrasOnWin(stars: stars, frenzyMoves: frenzyMoves)
        try await wait(0.4)
        audio.play(.WIN)
        audio.duck(true)
        dialog = .WIN
    }

    private func lose() async throws {
        phase = .LOST
        visuals.hint = nil
        try await wait(0.5)
        let livesBefore = save.state.livesNow().lives
        save.consumeLife()
        livesAfterLoss = (livesBefore - 1).coerceAtLeast(0)
        loseSummary = tracker.remainingSummary()
        extrasOnLose()
        audio.play(.LOSE)
        audio.duck(true)
        dialog = .LOSE
    }

    /// AdMob hook: a rewarded ad can call this to continue the same board with extra moves.
    func grantExtraMoves(_ n: Int) {
        if phase != .LOST { return }
        save.refundLife()
        tracker.movesLeft += n
        movesLeft = tracker.movesLeft
        audio.duck(false)
        dialog = .NONE
        phase = .PLAYING
        lastInteraction = time
        extrasOnContinue()
    }

    /// Debug builds only: finish the level immediately (QA shortcut).
    func debugFinish(win: Bool) {
        if phase != .PLAYING || busy { return }
        startTurn {
            if win {
                self.addScore(max(self.level.starScores[1], self.level.scoreTarget) + 100)
                try await self.win()
            } else {
                self.tracker.movesLeft = 0
                self.movesLeft = 0
                try await self.lose()
            }
        }
    }

    // ------------------------------------------------------------------ pause / dialogs

    var inProgress: Bool { phase == .INTRO || phase == .PLAYING || phase == .FRENZY }

    func pause() {
        if dialog != .NONE || !inProgress { return }
        paused = true
        dialog = .PAUSE
        visuals.hint = nil
    }

    func resume() {
        dialog = .NONE
        paused = false
        lastInteraction = time
    }

    /// App went to the background mid-level.
    func onBackground() {
        if dialog == .NONE && inProgress { pause() }
        extrasOnBackground()
    }

    /// Leaving costs a life once a move has been made (and the level is not finished).
    var leavingCostsLife: Bool { movesMade > 0 && inProgress }

    func askConfirmMap() { dialog = .CONFIRM_MAP }
    func askConfirmRestart() { dialog = .CONFIRM_RESTART }
    func backToPause() { dialog = .PAUSE }
    func showNoLives() { dialog = .NO_LIVES }

    func spendLifeForLeaving() {
        if leavingCostsLife { save.consumeLife() }
    }

    func livesNow() -> Int { save.state.livesNow().lives }

    func restart() {
        cancelTurn()
        paused = false
        dialog = .NONE
        audio.duck(false)
        introBannerAt = -100
        extrasOnRestart()
        setupBoard()
        startIntro()
    }

    /// True once [onCleared] ran; a cleared view model is never resumed.
    @ObservationIgnored private(set) var isCleared = false

    /// Kotlin `onCleared()` (+ the screen's frame-loop effect ending): the screen is gone for good.
    func onCleared() {
        isCleared = true
        cancelTurn()
        loop.stop()
        audio.duck(false)
    }
}
