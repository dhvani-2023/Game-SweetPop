import SwiftUI
import Observation

/// App-wide session state of the extras (not saved), owned by `AppContainer.extras`.
@MainActor
@Observable
final class ExtrasSession {
    /// Coins already added to the save that the map's coin pill has not counted up to yet: they fly into the pill
    /// (and the pill counts up) the next time the map is on screen.
    var coinsInFlight = 0

    /// Set by "Continue level N?": the game screen of that level restores it instead of starting fresh.
    @ObservationIgnored var pendingRestore: LevelSnapshot?

    func takeRestore(for level: Int) -> LevelSnapshot? {
        guard let s = pendingRestore, s.level == level else { return nil }
        pendingRestore = nil
        return s
    }

    /// Coins the pill may show right now.
    func shownCoins(_ saved: Int) -> Int { max(0, saved - coinsInFlight) }

    /// After spending: never hold back more coins than the save has.
    func clampInFlight(_ saved: Int) {
        if coinsInFlight > saved { coinsInFlight = max(0, saved) }
    }
}

/// What a Win-dialog button does once the episode chest has been shown.
enum AfterChest {
    case NEXT
    case MAP
}

/// Per-attempt state of the extras inside one `GameViewModel` (`vm.extras`).
@MainActor
@Observable
final class GameExtras {
    /// Hammer or Free Swap waiting for its target on the board.
    var armed: Booster?
    /// Booster whose shop dialog is open (`GameDialog.BOOSTER_SHOP`).
    var shop: Booster?
    /// Coins the win paid (Win dialog "+N coins").
    var winCoins = 0
    /// Episode chest the win paid, revealed after the Win dialog.
    var chest: ChestReward?
    @ObservationIgnored var chestShown = false
    @ObservationIgnored var afterChest: AfterChest?
    /// The free (rewarded) Lose-dialog "+5 Moves" was used this attempt.
    var freeMovesUsed = false
    /// Bumped to punch the HUD moves card (+5 Moves).
    var movesPunch = 0

    /// Lollipop Hammer swing: target cell and its start on the game clock.
    @ObservationIgnored var hammerAt: Pos?
    @ObservationIgnored var hammerStart: Float = -100
    /// HUD moves card centre in the game screen's root space (sparkles for +5 Moves).
    @ObservationIgnored var movesCardCenter: CGPoint?

    /// The board changed since the attempt started (a move or a booster): worth autosaving.
    @ObservationIgnored var dirty = false
    /// Last settled state of this attempt (written if the app is backgrounded while a turn is mid-flight).
    @ObservationIgnored var stable: LevelSnapshot?

    /// A level restored from the autosave continues this attempt.
    func restored(_ s: LevelSnapshot) {
        freeMovesUsed = s.freeMovesUsed
        dirty = true
        stable = s
    }

    func resetForAttempt() {
        armed = nil
        shop = nil
        winCoins = 0
        chest = nil
        chestShown = false
        afterChest = nil
        freeMovesUsed = false
        hammerAt = nil
        hammerStart = -100
        dirty = false
        stable = nil
    }
}
