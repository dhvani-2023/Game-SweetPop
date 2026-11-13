import Foundation
import Observation
import GameKit

/// The extras' saved values (new keys in the same "sweetpop" Prefs store; the Android keys are untouched).
struct ExtrasData: Equatable {
    let coins: Int
    let hammer: Int
    let swap: Int
    let moves: Int
    /// Epoch day (local calendar) of the last daily spin, −1 = never.
    let spinDay: Int
    /// Epoch day of the last login gift claimed, −1 = never.
    let loginDay: Int
    /// Gift day (1…7) of that claim, 0 = none.
    let loginStreak: Int
    /// The last episode whose chest was given (0 = none).
    let chestsClaimed: Int
    let colorBlind: Bool

    func count(_ b: Booster) -> Int {
        switch b {
        case .HAMMER: return hammer
        case .SWAP: return swap
        case .MOVES: return moves
        }
    }
}

/**
 * Coins, boosters, daily rewards, chests and the colour-blind setting, stored next to the Android keys:
 * `coins`, `booster_HAMMER` / `booster_SWAP` / `booster_MOVES` (missing = 2, the starting stock), `spinDay`,
 * `loginDay`, `loginStreak`, `chestsClaimed`, `colorBlind`.
 *
 * [extras] is observable: it registers an observation on itself and every write below notifies it, so views that
 * read it update (the Android-port `state` is not re-parsed for these writes). Writes are synchronous.
 */
extension SaveRepository {
    enum XK {
        static let coins = "coins"
        static let spinDay = "spinDay"
        static let loginDay = "loginDay"
        static let loginStreak = "loginStreak"
        static let chestsClaimed = "chestsClaimed"
        static let colorBlind = "colorBlind"
    }

    var extras: ExtrasData {
        access(keyPath: \.extras)
        let p = store
        return ExtrasData(
            coins: p.int(XK.coins, 0).coerceAtLeast(0),
            hammer: p.int(Booster.HAMMER.saveKey, Economy.START_BOOSTERS).coerceAtLeast(0),
            swap: p.int(Booster.SWAP.saveKey, Economy.START_BOOSTERS).coerceAtLeast(0),
            moves: p.int(Booster.MOVES.saveKey, Economy.START_BOOSTERS).coerceAtLeast(0),
            spinDay: p.int(XK.spinDay, -1),
            loginDay: p.int(XK.loginDay, -1),
            loginStreak: p.int(XK.loginStreak, 0),
            chestsClaimed: p.int(XK.chestsClaimed, 0),
            colorBlind: p.bool(XK.colorBlind, false)
        )
    }

    private func editExtras(_ block: (Prefs) -> Void) {
        withMutation(keyPath: \.extras) { block(store) }
    }

    private static func coins(_ p: Prefs) -> Int { p.int(XK.coins, 0).coerceAtLeast(0) }

    private static func boosters(_ p: Prefs, _ b: Booster) -> Int { p.int(b.saveKey, Economy.START_BOOSTERS).coerceAtLeast(0) }

    // ------------------------------------------------------------------ coins

    func addCoins(_ n: Int) {
        if n <= 0 { return }
        editExtras { $0.set(XK.coins, SaveRepository.coins($0) + n) }
    }

    /// Takes [n] coins if there are enough; false (and nothing changes) otherwise.
    @discardableResult
    func spendCoins(_ n: Int) -> Bool {
        let have = SaveRepository.coins(store)
        if n < 0 || have < n { return false }
        editExtras { $0.set(XK.coins, have - n) }
        return true
    }

    // ------------------------------------------------------------------ boosters

    func addBoosters(_ b: Booster, _ n: Int) {
        if n <= 0 { return }
        editExtras { $0.set(b.saveKey, SaveRepository.boosters($0, b) + n) }
    }

    /// Uses one [b]; false when there is none left.
    @discardableResult
    func useBooster(_ b: Booster) -> Bool {
        let have = SaveRepository.boosters(store, b)
        if have <= 0 { return false }
        editExtras { $0.set(b.saveKey, have - 1) }
        return true
    }

    /// Buys one [b] for its price; false when the coins don't cover it.
    @discardableResult
    func buyBooster(_ b: Booster) -> Bool {
        let have = SaveRepository.coins(store)
        if have < b.price { return false }
        editExtras { p in
            p.set(XK.coins, have - b.price)
            p.set(b.saveKey, SaveRepository.boosters(p, b) + 1)
        }
        return true
    }

    // ------------------------------------------------------------------ daily rewards

    /// Spends today's spin and grants its prize. Coin and booster prizes land here; a life goes through
    /// `refundLife` (capped at the maximum, like a regenerated life).
    func recordSpin(day: Int, prize: DailySpin.Prize, now: Int64 = Days.nowMillis()) {
        editExtras { p in
            p.set(XK.spinDay, day)
            switch prize {
            case .coins(let n): p.set(XK.coins, SaveRepository.coins(p) + n)
            case .booster(let b): p.set(b.saveKey, SaveRepository.boosters(p, b) + 1)
            case .life: break
            }
        }
        if prize == .life { refundLife(now: now) }
    }

    /// Claims the login gift of streak day [day] (1…7) on [today]; day 7 also gives one of each booster.
    func claimLoginGift(day: Int, today: Int) {
        editExtras { p in
            p.set(XK.coins, SaveRepository.coins(p) + LoginGift.coins(day: day))
            let extra = LoginGift.boostersPerKind(day: day)
            if extra > 0 {
                for b in Booster.allCases { p.set(b.saveKey, SaveRepository.boosters(p, b) + extra) }
            }
            p.set(XK.loginDay, today)
            p.set(XK.loginStreak, day)
        }
    }

    /// Grants an episode chest (coins + its booster) and marks the episode as paid.
    func claimChest(_ r: ChestReward) {
        editExtras { p in
            p.set(XK.coins, SaveRepository.coins(p) + r.coins)
            p.set(r.booster.saveKey, SaveRepository.boosters(p, r.booster) + 1)
            p.set(XK.chestsClaimed, max(p.int(XK.chestsClaimed, 0), r.episode))
        }
    }

    // ------------------------------------------------------------------ settings / reset

    func setColorBlind(_ on: Bool) { editExtras { $0.set(XK.colorBlind, on) } }

    /// "Reset Progress" with the extras on: coins, boosters (back to the starting 2) and chests start over.
    /// The daily spin / login calendar (so today's rewards can't be claimed twice) and the colour-blind setting stay.
    func resetExtrasProgress() {
        editExtras { p in
            p.remove(XK.coins)
            for b in Booster.allCases { p.remove(b.saveKey) }
            p.remove(XK.chestsClaimed)
        }
    }
}
