import XCTest
import Observation
import GameKit
@testable import SweetPop

/// iOS extras: coin maths, boosters, daily spin / login streak day logic, episode chests and their save keys
/// (same "sweetpop" Prefs store as the Android port).
final class ExtrasEconomyTest: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "sweetpop-extras-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func repo() -> SaveRepository { SaveRepository(store: Prefs(name: "sweetpop", defaults: defaults)) }

    // ------------------------------------------------------------------ coins

    func testWinCoinsAre20Plus10PerStarPlus2PerFrenzyMove() {
        XCTAssertEqual(30, Economy.winCoins(stars: 1, frenzyMoves: 0))
        XCTAssertEqual(40, Economy.winCoins(stars: 2, frenzyMoves: 0))
        XCTAssertEqual(50, Economy.winCoins(stars: 3, frenzyMoves: 0))
        XCTAssertEqual(50 + 7 * 2, Economy.winCoins(stars: 3, frenzyMoves: 7))
        XCTAssertEqual(30 + 2, Economy.winCoins(stars: 1, frenzyMoves: 1))
        // Out-of-range inputs are clamped.
        XCTAssertEqual(50, Economy.winCoins(stars: 9, frenzyMoves: -4))
        XCTAssertEqual(20, Economy.winCoins(stars: 0, frenzyMoves: 0))
    }

    func testBoosterPricesAndKeys() {
        XCTAssertEqual(100, Booster.HAMMER.price)
        XCTAssertEqual(80, Booster.SWAP.price)
        XCTAssertEqual(150, Booster.MOVES.price)
        XCTAssertEqual(["booster_HAMMER", "booster_SWAP", "booster_MOVES"], Booster.allCases.map(\.saveKey))
        XCTAssertEqual(5, Economy.EXTRA_MOVES)
    }

    func testDefaultsStartWithTwoOfEachBoosterAndNoCoins() {
        let ex = repo().extras
        XCTAssertEqual(0, ex.coins)
        for b in Booster.allCases { XCTAssertEqual(2, ex.count(b)) }
        XCTAssertEqual(-1, ex.spinDay)
        XCTAssertEqual(-1, ex.loginDay)
        XCTAssertEqual(0, ex.loginStreak)
        XCTAssertEqual(0, ex.chestsClaimed)
        XCTAssertFalse(ex.colorBlind)
        XCTAssertNil(defaults.object(forKey: "sweetpop.coins")) // nothing written until something changes
    }

    func testCoinsAndBoostersUseTheSweetpopStore() {
        let r = repo()
        r.addCoins(120)
        XCTAssertEqual(120, defaults.integer(forKey: "sweetpop.coins"))
        XCTAssertFalse(r.buyBooster(.MOVES)) // 150 > 120: nothing changes
        XCTAssertEqual(120, r.extras.coins)
        XCTAssertEqual(2, r.extras.moves)
        r.addCoins(100)
        XCTAssertTrue(r.buyBooster(.MOVES))
        XCTAssertEqual(70, r.extras.coins)
        XCTAssertEqual(3, r.extras.moves)
        XCTAssertEqual(3, defaults.integer(forKey: "sweetpop.booster_MOVES"))

        XCTAssertTrue(r.useBooster(.HAMMER))
        XCTAssertTrue(r.useBooster(.HAMMER))
        XCTAssertFalse(r.useBooster(.HAMMER))
        XCTAssertEqual(0, r.extras.hammer)
        XCTAssertEqual(0, defaults.integer(forKey: "sweetpop.booster_HAMMER"))

        XCTAssertFalse(r.spendCoins(71))
        XCTAssertTrue(r.spendCoins(70))
        XCTAssertEqual(0, r.extras.coins)
        r.addCoins(-50) // ignored
        XCTAssertEqual(0, r.extras.coins)

        // A second repository on the same store reads the same values.
        let again = repo().extras
        XCTAssertEqual(0, again.hammer)
        XCTAssertEqual(3, again.moves)
        XCTAssertEqual(2, again.swap)
    }

    func testExtrasAreObservable() {
        final class Flag: @unchecked Sendable { var set = false }
        let r = repo()
        let changed = Flag()
        withObservationTracking {
            _ = r.extras.coins
        } onChange: {
            changed.set = true
        }
        r.addCoins(5)
        XCTAssertTrue(changed.set)
    }

    func testResetKeepsTheDailyCalendarAndColourBlindSetting() {
        let r = repo()
        r.addCoins(500)
        r.addBoosters(.SWAP, 3)
        r.claimChest(ChestReward(episode: 2, coins: 100, booster: .HAMMER))
        r.recordSpin(day: 300, prize: .coins(25))
        r.claimLoginGift(day: 4, today: 300)
        r.setColorBlind(true)
        r.resetExtrasProgress()
        let ex = r.extras
        XCTAssertEqual(0, ex.coins)
        for b in Booster.allCases { XCTAssertEqual(Economy.START_BOOSTERS, ex.count(b)) }
        XCTAssertEqual(0, ex.chestsClaimed)
        XCTAssertEqual(300, ex.spinDay)
        XCTAssertEqual(300, ex.loginDay)
        XCTAssertEqual(4, ex.loginStreak)
        XCTAssertTrue(ex.colorBlind)
        XCTAssertTrue(defaults.bool(forKey: "sweetpop.colorBlind"))
    }

    // ------------------------------------------------------------------ daily spin

    func testSpinOncePerLocalDay() {
        XCTAssertTrue(DailySpin.isAvailable(spinDay: -1, today: 20_000))
        XCTAssertTrue(DailySpin.isAvailable(spinDay: 19_999, today: 20_000))
        XCTAssertFalse(DailySpin.isAvailable(spinDay: 20_000, today: 20_000))
        // Clock moved back before the last spin: no extra spin.
        XCTAssertFalse(DailySpin.isAvailable(spinDay: 20_001, today: 20_000))
    }

    func testWheelHasTheEightPrizes() {
        let prizes = DailySpin.segments.map(\.prize)
        XCTAssertEqual(8, prizes.count)
        for p in [DailySpin.Prize.coins(25), .coins(50), .coins(100), .coins(200), .booster(.HAMMER), .booster(.SWAP), .booster(.MOVES), .life] {
            XCTAssertTrue(prizes.contains(p), "missing \(p)")
        }
        XCTAssertEqual(100, DailySpin.segments.reduce(0) { $0 + $1.weight })
    }

    func testSpinPickFollowsTheWeights() {
        let n = 100_000
        var counts = [Int](repeating: 0, count: DailySpin.count)
        for i in 0..<n { counts[DailySpin.pick(roll: (Double(i) + 0.5) / Double(n), livesFull: false)] += 1 }
        for (i, s) in DailySpin.segments.enumerated() {
            XCTAssertEqual(s.weight * n / 100, counts[i], "segment \(i)")
        }
        XCTAssertEqual(0, DailySpin.pick(roll: 0, livesFull: false))
        XCTAssertEqual(DailySpin.count - 1, DailySpin.pick(roll: 0.9999, livesFull: false))
        XCTAssertEqual(DailySpin.count - 1, DailySpin.pick(roll: 1.5, livesFull: false))
    }

    func testFullLivesNeverWinALife() {
        let life = DailySpin.segments.firstIndex { $0.prize == .life }!
        for i in 0..<10_000 {
            XCTAssertNotEqual(life, DailySpin.pick(roll: Double(i) / 10_000, livesFull: true))
        }
    }

    func testSpinPrizesLandInTheSave() {
        let r = repo()
        r.recordSpin(day: 10, prize: .coins(100))
        XCTAssertEqual(100, r.extras.coins)
        XCTAssertEqual(10, r.extras.spinDay)
        XCTAssertEqual(10, defaults.integer(forKey: "sweetpop.spinDay"))
        r.recordSpin(day: 11, prize: .booster(.SWAP))
        XCTAssertEqual(3, r.extras.swap)
        r.consumeLife(now: 1_000)
        XCTAssertEqual(Lives.MAX - 1, r.state.lives)
        r.recordSpin(day: 12, prize: .life, now: 2_000)
        XCTAssertEqual(Lives.MAX, r.state.lives)
        XCTAssertEqual(12, r.extras.spinDay)
    }

    // ------------------------------------------------------------------ login gift

    func testLoginStreakDays() {
        XCTAssertEqual(1, LoginGift.dayToClaim(lastDay: -1, lastStreak: 0, today: 500)) // first ever
        XCTAssertEqual(2, LoginGift.dayToClaim(lastDay: 499, lastStreak: 1, today: 500))
        XCTAssertEqual(7, LoginGift.dayToClaim(lastDay: 499, lastStreak: 6, today: 500))
        XCTAssertEqual(1, LoginGift.dayToClaim(lastDay: 499, lastStreak: 7, today: 500)) // wraps after day 7
        XCTAssertEqual(1, LoginGift.dayToClaim(lastDay: 498, lastStreak: 5, today: 500)) // missed a day: reset
        XCTAssertEqual(1, LoginGift.dayToClaim(lastDay: 400, lastStreak: 3, today: 500))
        XCTAssertNil(LoginGift.dayToClaim(lastDay: 500, lastStreak: 3, today: 500)) // already claimed today
        XCTAssertNil(LoginGift.dayToClaim(lastDay: 501, lastStreak: 3, today: 500)) // clock moved back
        XCTAssertEqual(1, LoginGift.dayToClaim(lastDay: 499, lastStreak: 0, today: 500)) // corrupt streak
    }

    func testLoginGiftTable() {
        XCTAssertEqual([20, 30, 40, 60, 80, 100, 200], (1...7).map { LoginGift.coins(day: $0) })
        XCTAssertEqual([0, 0, 0, 0, 0, 0, 1], (1...7).map { LoginGift.boostersPerKind(day: $0) })
    }

    func testSevenDayStreakThroughTheRepository() {
        let r = repo()
        var today = 1_000
        for expected in 1...7 {
            let ex = r.extras
            let d = LoginGift.dayToClaim(lastDay: ex.loginDay, lastStreak: ex.loginStreak, today: today)
            XCTAssertEqual(expected, d)
            r.claimLoginGift(day: d!, today: today)
            XCTAssertNil(LoginGift.dayToClaim(lastDay: r.extras.loginDay, lastStreak: r.extras.loginStreak, today: today))
            today += 1
        }
        let ex = r.extras
        XCTAssertEqual(20 + 30 + 40 + 60 + 80 + 100 + 200, ex.coins)
        for b in Booster.allCases { XCTAssertEqual(Economy.START_BOOSTERS + 1, ex.count(b)) }
        XCTAssertEqual(7, defaults.integer(forKey: "sweetpop.loginStreak"))
        XCTAssertEqual(1_006, defaults.integer(forKey: "sweetpop.loginDay"))
        // Day 8 starts a new week; skipping day 9 resets it.
        XCTAssertEqual(1, LoginGift.dayToClaim(lastDay: ex.loginDay, lastStreak: ex.loginStreak, today: today))
        r.claimLoginGift(day: 1, today: today)
        XCTAssertEqual(1, LoginGift.dayToClaim(lastDay: r.extras.loginDay, lastStreak: r.extras.loginStreak, today: today + 2))
    }

    // ------------------------------------------------------------------ episode chest

    func testChestAtTheEndOfEachEpisodeOnce() {
        XCTAssertEqual(1, EpisodeChest.episodeEnding(at: 20))
        XCTAssertEqual(2, EpisodeChest.episodeEnding(at: 40))
        XCTAssertEqual(100, EpisodeChest.episodeEnding(at: 2000))
        XCTAssertNil(EpisodeChest.episodeEnding(at: 19))
        XCTAssertNil(EpisodeChest.episodeEnding(at: 21))
        XCTAssertNil(EpisodeChest.episodeEnding(at: 0))
        XCTAssertTrue(EpisodeChest.isDue(level: 20, claimed: 0))
        XCTAssertFalse(EpisodeChest.isDue(level: 20, claimed: 1)) // replay
        XCTAssertTrue(EpisodeChest.isDue(level: 40, claimed: 1))
        XCTAssertTrue(EpisodeChest.isDue(level: 60, claimed: 0)) // a player who was past 40 when chests arrived
        XCTAssertFalse(EpisodeChest.isDue(level: 39, claimed: 0))

        let r = repo()
        r.claimChest(ChestReward(episode: 3, coins: EpisodeChest.COINS, booster: .SWAP))
        XCTAssertEqual(100, r.extras.coins)
        XCTAssertEqual(3, r.extras.swap)
        XCTAssertEqual(3, r.extras.chestsClaimed)
        XCTAssertEqual(3, defaults.integer(forKey: "sweetpop.chestsClaimed"))
        XCTAssertFalse(EpisodeChest.isDue(level: 60, claimed: r.extras.chestsClaimed))
        XCTAssertTrue(EpisodeChest.isDue(level: 80, claimed: r.extras.chestsClaimed))
    }
}
