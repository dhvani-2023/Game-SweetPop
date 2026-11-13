import SwiftUI
import GameKit

/// The extras' side of a level: boosters, coins and the chest on a win, the Lose-dialog "+5 Moves" offer and the
/// autosave. Hooks in GameViewModel.swift call the `extras…` methods; every feature checks its `Features` flag.
extension GameViewModel {
    /// Lollipop Hammer swing until it hits the candy (game-clock seconds).
    static let HAMMER_IMPACT: Float = 0.17

    // ------------------------------------------------------------------ booster bar

    /// Booster bar tap: arms Hammer / Free Swap (tap again to put it away), uses +5 Moves at once, or opens the
    /// shop when none are left.
    func onBoosterTap(_ b: Booster) {
        guard Features.boosters else { return }
        if extras.armed == b {
            extras.armed = nil
            visuals.selected = nil
            return
        }
        guard acceptsInput else { return }
        if save.extras.count(b) > 0 {
            activate(b)
        } else if Features.economy {
            visuals.selected = nil
            visuals.hint = nil
            extras.shop = b
            dialog = .BOOSTER_SHOP
        } else {
            audio.play(.SWAP_BACK, volume: 0.6)
        }
    }

    /// Shop "Buy": pays and uses the booster straight away.
    func buyBooster(_ b: Booster) {
        guard dialog == .BOOSTER_SHOP, save.buyBooster(b) else { return }
        container.extras.clampInFlight(save.extras.coins)
        audio.play(.UNLOCK, volume: 0.7)
        haptics.medium()
        closeShop()
        activate(b)
    }

    func closeShop() {
        if dialog == .BOOSTER_SHOP { dialog = .NONE }
        lastInteraction = time
    }

    private func activate(_ b: Booster) {
        switch b {
        case .MOVES:
            guard acceptsInput, save.useBooster(.MOVES) else { return }
            extras.armed = nil
            addMoves(Economy.EXTRA_MOVES)
        case .HAMMER, .SWAP:
            extras.armed = b
            visuals.selected = nil
            visuals.hint = nil
            lastInteraction = time
            let c = screenCenter
            effects.banner(b.armedHint, c.x, c.y, 30, Color(argb: 0xFFFFE27A))
            audio.play(.SPECIAL, volume: 0.45)
            haptics.light()
        }
    }

    /// +5 Moves (booster bar): more moves on the same board, no move used.
    private func addMoves(_ n: Int) {
        tracker.movesLeft += n
        movesLeft = tracker.movesLeft
        extras.dirty = true
        extras.stable = makeSnapshot()
        celebrateMoves(n)
    }

    private func celebrateMoves(_ n: Int) {
        extras.movesPunch &+= 1
        let c = screenCenter
        effects.banner("+\(n) Moves!", c.x, c.y, 40, Color(argb: 0xFFB8FFCF))
        if let m = extras.movesCardCenter {
            effects.sparkles(Float(m.x), Float(m.y), 10, 34, 14, Color(argb: 0xFFFFF4B0))
        }
        audio.play(.UNLOCK, volume: 0.8)
        haptics.medium()
    }

    // ------------------------------------------------------------------ board input while a booster is armed

    /// A board tap with the Hammer out smashes that candy. True when the tap was used.
    func extrasTap(_ p: Pos) -> Bool {
        guard Features.boosters, extras.armed == .HAMMER else { return false }
        guard board.candyAt(p) != nil else {
            audio.play(.SWAP_BACK, volume: 0.5)
            return true
        }
        guard save.useBooster(.HAMMER) else {
            extras.armed = nil
            return true
        }
        extras.armed = nil
        extras.dirty = true
        visuals.selected = nil
        visuals.hint = nil
        startTurn { try await self.hammerTurn(p) }
        return true
    }

    /// A swap with Free Swap out happens even without a match and uses no move. True when handled
    /// (with the Hammer out, swipes do nothing).
    func extrasSwap(_ a: Pos, _ b: Pos) -> Bool {
        guard Features.boosters, let armed = extras.armed else { return false }
        if armed == .HAMMER { return true }
        guard armed == .SWAP, let ca = board.candyAt(a), let cb = board.candyAt(b) else { return false }
        if ca.color == cb.color && ca.special == cb.special {
            // Nothing would change: keep the booster.
            audio.play(.SWAP_BACK, volume: 0.6)
            return true
        }
        guard save.useBooster(.SWAP) else {
            extras.armed = nil
            return true
        }
        extras.armed = nil
        extras.dirty = true
        visuals.selected = nil
        visuals.hint = nil
        startTurn { try await self.freeSwapTurn(a, b) }
        return true
    }

    private func hammerTurn(_ p: Pos) async throws {
        extras.hammerAt = p
        extras.hammerStart = time
        audio.play(.WHOOSH, volume: 0.4)
        try await wait(Self.HAMMER_IMPACT)
        let c = center(p)
        effects.shockwave(c.x, c.y, cellPx * 1.3, Color(argb: 0xFFFFE3F1))
        effects.shake(10 * px)
        effects.sparkles(c.x, c.y, 7, cellPx * 0.5, cellPx * 0.3, Color(argb: 0xFFFFF4B0))
        audio.play(.FROSTING, volume: 0.9)
        haptics.heavy()
        guard engine.beginHammer(p) else { return }
        try await runWaves()
        try await spawnCreated()
        try await gravity()
        try await cascadeLoop(nil, 1)
        try await settle()
    }

    private func freeSwapTurn(_ a: Pos, _ b: Pos) async throws {
        guard let ca = board.candyAt(a), let cb = board.candyAt(b) else { return }
        audio.play(.SWAP, volume: 0.8)
        audio.play(.SPECIAL, volume: 0.3)
        haptics.light()
        engine.swap(a, b)
        visuals.motions[ca.id] = Motion(Float(a.x), Float(a.y), Float(b.x), Float(b.y), time, 0.24, .IN_OUT)
        visuals.motions[cb.id] = Motion(Float(b.x), Float(b.y), Float(a.x), Float(a.y), time, 0.24, .IN_OUT)
        let ka = center(a)
        let kb = center(b)
        effects.sparkles((ka.x + kb.x) / 2, (ka.y + kb.y) / 2, 8, cellPx * 0.6, cellPx * 0.26, Color(argb: 0xFFB8F0FF))
        try await wait(0.24)
        if engine.isComboSwap(a, b) {
            try await runCombo(a, b)
            try await cascadeLoop(nil, 1)
        } else {
            let groups = MatchFinder.findGroups(board, swappedInto: b, other: a)
            if !groups.isEmpty { try await cascadeLoop(groups, 0) }
        }
        try await settle()
    }

    // ------------------------------------------------------------------ Lose dialog: +5 Moves

    /// The one "+5 Moves" offer on the Lose dialog: free (rewarded seam) once per attempt, then a booster if any
    /// is left, else 150 coins.
    func extraMovesOffer(_ ex: ExtrasData) -> ExtraMovesOffer {
        if !extras.freeMovesUsed && Ads.rewarded.isAvailable {
            return ExtraMovesOffer(kind: .free, coins: ex.coins) { [weak self] in self?.takeFreeExtraMoves() }
        }
        if ex.moves > 0 {
            return ExtraMovesOffer(kind: .booster(ex.moves), coins: ex.coins) { [weak self] in self?.useExtraMovesBooster() }
        }
        return ExtraMovesOffer(kind: .coins(Booster.MOVES.price), coins: ex.coins) { [weak self] in self?.buyExtraMoves() }
    }

    private func takeFreeExtraMoves() {
        guard phase == .LOST, !extras.freeMovesUsed else { return }
        Ads.rewarded.show("lose_extra_moves") { [weak self] granted in
            guard let self, granted, self.phase == .LOST, !self.extras.freeMovesUsed else { return }
            self.extras.freeMovesUsed = true
            self.grantExtraMoves(Economy.EXTRA_MOVES)
        }
    }

    private func useExtraMovesBooster() {
        guard phase == .LOST, save.useBooster(.MOVES) else { return }
        grantExtraMoves(Economy.EXTRA_MOVES)
    }

    private func buyExtraMoves() {
        guard phase == .LOST, save.spendCoins(Booster.MOVES.price) else { return }
        container.extras.clampInFlight(save.extras.coins)
        grantExtraMoves(Economy.EXTRA_MOVES)
    }

    // ------------------------------------------------------------------ episode chest

    /// Win-dialog Next / Map: shows the episode chest first when this win earned one. True when it did.
    func showChestIfDue(_ after: AfterChest) -> Bool {
        guard Features.episodeChest, extras.chest != nil, !extras.chestShown, phase == .WON else { return false }
        extras.chestShown = true
        extras.afterChest = after
        dialog = .CHEST
        return true
    }

    /// Chest "Collect": what the Win-dialog button wanted to do.
    func finishChest() -> AfterChest? {
        let a = extras.afterChest
        extras.afterChest = nil
        return a
    }

    // ------------------------------------------------------------------ hooks from GameViewModel.swift

    func extrasFrenzyStarted() {
        extras.armed = nil
    }

    /// Win recorded: coins (20 + 10 per star + 2 per Sweet Frenzy move), the episode chest, autosave cleared.
    func extrasOnWin(stars: Int, frenzyMoves: Int) {
        extras.armed = nil
        extras.stable = nil
        if Features.autosave { AutoSave.clear() }
        if Features.economy {
            let coins = Economy.winCoins(stars: stars, frenzyMoves: frenzyMoves)
            save.addCoins(coins)
            container.extras.coinsInFlight += coins
            extras.winCoins = coins
        }
        if Features.episodeChest, EpisodeChest.isDue(level: levelNumber, claimed: save.extras.chestsClaimed),
           let episode = EpisodeChest.episodeEnding(at: levelNumber) {
            let reward = ChestReward(episode: episode, coins: EpisodeChest.COINS, booster: Booster.allCases.randomElement() ?? .HAMMER)
            save.claimChest(reward)
            if Features.economy { container.extras.coinsInFlight += reward.coins }
            extras.chest = reward
        }
    }

    func extrasOnLose() {
        extras.armed = nil
        extras.stable = nil
        if Features.autosave { AutoSave.clear() }
    }

    /// Continued after a loss with +5 moves.
    func extrasOnContinue() {
        extras.dirty = true
        extras.stable = makeSnapshot()
        celebrateMoves(Economy.EXTRA_MOVES)
    }

    func extrasOnRestart() {
        extras.resetForAttempt()
        if Features.autosave { AutoSave.clear() }
    }

    /// Left for the map mid-level (pause › Map): Android's life rules apply, the autosave goes.
    func extrasOnQuit() {
        extras.stable = nil
        if Features.autosave { AutoSave.clear() }
    }

    /// A turn finished: remember the settled board for a background autosave.
    func extrasTurnEnded() {
        guard Features.autosave, phase == .PLAYING, movesMade > 0 || extras.dirty else { return }
        extras.dirty = true
        extras.stable = makeSnapshot()
    }

    /// App went to the background: save the level in progress. Mid-turn, the last settled state is written.
    func extrasOnBackground() {
        guard Features.autosave, inProgress, movesMade > 0 || extras.dirty else { return }
        let snap = phase == .PLAYING && !busy ? makeSnapshot() : extras.stable
        if let snap { AutoSave.write(snap) }
    }

    func makeSnapshot() -> LevelSnapshot {
        LevelSnapshot(
            level: level, board: board, tracker: tracker, starsLit: starsLit, movesMade: movesMade,
            freeMovesUsed: extras.freeMovesUsed
        )
    }
}

/// The Lose dialog's "+5 Moves" button: what it costs and what it does.
struct ExtraMovesOffer {
    enum Kind: Equatable {
        /// Rewarded seam (`Ads.rewarded`), labelled FREE while no real ads are configured.
        case free
        /// Uses one of the player's +5 Moves boosters (count shown).
        case booster(Int)
        /// Buys it for this many coins.
        case coins(Int)
    }

    let kind: Kind
    let coins: Int
    let onTake: () -> Void

    var affordable: Bool {
        if case .coins(let price) = kind { return coins >= price }
        return true
    }
}
