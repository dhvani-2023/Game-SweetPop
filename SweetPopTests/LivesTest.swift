import XCTest
@testable import SweetPop

final class LivesTest: XCTestCase {
    private let r = Lives.REGEN_MS

    func testConsumeStartsTimer() {
        let s = Lives.consume(5, 0, 1000)
        XCTAssertEqual(4, s.lives)
        XCTAssertEqual(1000 + r, s.nextLifeAtMillis)
    }

    func testRegeneratesOverTime() {
        // A life was due at 1000 and another at 1000 + r.
        let s = Lives.refresh(2, 1000, 1000 + r + 5)
        XCTAssertEqual(4, s.lives)
        XCTAssertEqual(1000 + r * 2, s.nextLifeAtMillis)
        let full = Lives.refresh(2, 1000, 1000 + r * 10)
        XCTAssertEqual(5, full.lives)
        XCTAssertEqual(0, full.nextLifeAtMillis)
    }

    func testClockMovedBackIsClamped() {
        let s = Lives.refresh(3, 10_000_000, 0)
        XCTAssertEqual(3, s.lives)
        XCTAssertEqual(r, s.nextLifeAtMillis)
    }

    func testTimerText() {
        XCTAssertEqual("Full", Lives.timerText(Lives.State(5, 0), 0))
        XCTAssertEqual("19:59", Lives.timerText(Lives.State(4, r), 1000))
    }
}
