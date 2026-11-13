import XCTest
import GameKit
@testable import SweetPop

/// Not a JUnit port (Android has no SaveRepository test): pins the DataStore key names ("sweetpop" store) and the
/// value encodings, so a save means the same thing on both platforms.
final class SaveRepositoryTest: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "sweetpop-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func repo() -> SaveRepository { SaveRepository(store: Prefs(name: "sweetpop", defaults: defaults)) }

    func testDefaults() {
        let s = repo().state
        XCTAssertTrue(s.loaded)
        XCTAssertEqual(1, s.highestUnlocked)
        XCTAssertEqual(LEVEL_COUNT, s.stars.count)
        XCTAssertEqual(LEVEL_COUNT, s.bestScores.count)
        XCTAssertEqual(Lives.MAX, s.lives)
        XCTAssertEqual(0, s.nextLifeAtMillis)
        XCTAssertTrue(s.music && s.sfx && s.vibration && s.hints)
        XCTAssertEqual(0, s.theme)
        XCTAssertFalse(s.onboardingDone || s.termsAccepted)
        XCTAssertEqual(1, s.lastPlayedLevel)
        XCTAssertEqual(0, s.totalStars)
    }

    func testRecordWinUsesAndroidEncodings() {
        let r = repo()
        r.recordWin(3, 2, 4100)
        r.recordWin(1, 5, 900) // stars clamp to 3
        r.recordWin(3, 1, 3000) // best stars and best score are kept
        XCTAssertEqual("302", defaults.string(forKey: "sweetpop.stars")) // digits, trailing zeros dropped
        let bests = defaults.string(forKey: "sweetpop.bestScores")!.split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(LEVEL_COUNT, bests.count) // every level, comma-joined
        XCTAssertEqual(["900", "0", "4100"], bests.prefix(3).map(String.init))
        XCTAssertEqual(4, defaults.integer(forKey: "sweetpop.highestUnlocked"))
        XCTAssertEqual(3, defaults.integer(forKey: "sweetpop.lastPlayedLevel"))
        XCTAssertEqual(3, r.state.starsFor(1))
        XCTAssertEqual(4100, r.state.bestFor(3))
        XCTAssertEqual(0, r.state.bestFor(0))
        XCTAssertEqual(5, r.state.totalStars)
        XCTAssertEqual(4, r.state.highestUnlocked)
    }

    func testDecodingIsTolerantLikeKotlin() {
        defaults.set("39x1", forKey: "sweetpop.stars") // (char - '0').coerceIn(0, 3)
        defaults.set("12,,abc,-5,+7,99999999999", forKey: "sweetpop.bestScores") // toIntOrNull() ?: 0
        defaults.set(99_999, forKey: "sweetpop.highestUnlocked") // coerced on read
        let s = repo().state
        XCTAssertEqual([3, 3, 3, 1, 0], Array(s.stars.prefix(5)))
        XCTAssertEqual([12, 0, 0, -5, 7, 0, 0], Array(s.bestScores.prefix(7)))
        XCTAssertEqual(LEVEL_COUNT, s.highestUnlocked)
    }

    func testLivesAndResetKeepSettings() {
        let r = repo()
        r.setMusic(false)
        r.setTheme(2)
        r.completeOnboarding()
        r.consumeLife(now: 1000)
        XCTAssertEqual(4, defaults.integer(forKey: "sweetpop.lives"))
        XCTAssertEqual(1000 + Lives.REGEN_MS, (defaults.object(forKey: "sweetpop.nextLifeAtMillis") as? NSNumber)?.int64Value)
        XCTAssertEqual(4, r.state.livesNow(now: 2000).lives)
        r.refundLife(now: 2000)
        XCTAssertEqual(Lives.MAX, r.state.lives)
        XCTAssertEqual(0, r.state.nextLifeAtMillis)
        r.recordWin(1, 3, 5000)
        r.resetProgress()
        let s = r.state
        XCTAssertEqual(1, s.highestUnlocked)
        XCTAssertEqual(0, s.totalStars)
        XCTAssertNil(defaults.object(forKey: "sweetpop.stars"))
        XCTAssertNil(defaults.object(forKey: "sweetpop.lives"))
        XCTAssertFalse(s.music)
        XCTAssertEqual(2, s.theme)
        XCTAssertTrue(s.onboardingDone && s.termsAccepted)
    }
}
