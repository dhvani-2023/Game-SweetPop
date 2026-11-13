import XCTest
@testable import SweetPop

final class LevelGeneratorTest: XCTestCase {

    /// `assertTrue(msg, cond)` without XCTest's per-call cost on the ~2 million passing checks.
    private func check(_ cond: Bool, _ msg: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) {
        if !cond { XCTFail(msg(), file: file, line: line) }
    }

    func testAllLevelsAreValid() {
        for n in 1...LevelCatalog.LEVEL_COUNT {
            let l = LevelGenerator.generate(n)
            let tag = "level \(n)"
            check(l.number == n, tag)
            check((4...6).contains(l.colors), "\(tag) colours")
            check((10...60).contains(l.moves), "\(tag) moves \(l.moves)")
            check(l.starScores[1] <= l.starScores[2], "\(tag) stars")
            check(l.starScores[0] <= l.starScores[1], "\(tag) stars0")
            switch l.goal {
            case .JELLY:
                check(l.jelly.contains { $0 > 0 }, "\(tag) jelly")
            case .FROSTING:
                check(l.frosting.contains { $0 > 0 }, "\(tag) frosting")
            case .COLLECT:
                check(!l.collect.isEmpty, "\(tag) collect")
                for t in l.collect { check(t.color.ordinal < l.colors && t.count > 0, "\(tag) collect colour") }
            case .SCORE:
                check(l.scoreTarget >= 1000, "\(tag) target")
            }
            for y in 0..<l.height {
                for x in 0..<l.width {
                    let i = l.idx(x, y)
                    if !l.playable[i] {
                        check(l.jelly[i] == 0, "\(tag) jelly on hole")
                        check(l.frosting[i] == 0, "\(tag) frosting on hole")
                        check(l.initial[i] == -1, "\(tag) candy on hole")
                    }
                    if l.frosting[i] > 0 { check(l.jelly[i] == 0, "\(tag) jelly under frosting") }
                }
            }
            for x in 0..<l.width {
                var top = -1
                var y = l.height - 1
                while y >= 0 {
                    if l.playable[l.idx(x, y)] {
                        top = y
                        break
                    }
                    y -= 1
                }
                if top >= 0 { check(l.frosting[l.idx(x, top)] == 0, "\(tag) frosting on top cell of column \(x)") }
            }
            check(LevelGenerator.isRefillable(l), "\(tag) has a cell under frosting that can never refill")
            let board = Board.fromLevel(l) { 1 }
            check(!MatchFinder.hasMatch(board), "\(tag) initial matches")
        }
    }

    func testLevelsAreDeterministic() {
        for n in [1, 7, 99, 500, 1234, 2000] {
            let a = LevelGenerator.generate(n)
            let b = LevelGenerator.generate(n)
            XCTAssertEqual(a.initial, b.initial)
            XCTAssertEqual(a.jelly, b.jelly)
            XCTAssertEqual(a.frosting, b.frosting)
            XCTAssertEqual(a.moves, b.moves)
            XCTAssertEqual(a.goal, b.goal)
        }
    }

    func testMostLevelsStartWithAValidMove() {
        var ok = 0
        for n in 1...LevelCatalog.LEVEL_COUNT {
            let board = Board.fromLevel(LevelGenerator.generate(n)) { 1 }
            if MatchFinder.findValidMove(board) != nil { ok += 1 }
        }
        XCTAssertEqual(LevelCatalog.LEVEL_COUNT, ok)
    }

    func testTutorialsMatchSpec() {
        let l1 = LevelGenerator.generate(1)
        XCTAssertEqual(7, l1.width)
        XCTAssertEqual(4, l1.colors)
        XCTAssertEqual(15, l1.moves)
        XCTAssertEqual([2000, 3500, 5500], l1.starScores)
        let l3 = LevelGenerator.generate(3)
        XCTAssertEqual(GoalType.COLLECT, l3.goal)
        XCTAssertEqual(1, l3.collect.count) // Kotlin single()
        XCTAssertEqual(20, l3.collect.first?.count)
        XCTAssertFalse(l3.playable[0])
        let l5 = LevelGenerator.generate(5)
        XCTAssertEqual(6, l5.frosting.filter { $0 > 0 }.count)
        let l6 = LevelGenerator.generate(6)
        XCTAssertEqual(27, l6.jelly.reduce(0, +))
    }

    func testEpisodeNames() {
        XCTAssertEqual("Lollipop Lane", LevelCatalog.episodeName(0))
        XCTAssertEqual("Caramel Canyon", LevelCatalog.episodeName(2))
        XCTAssertFalse(LevelCatalog.episodeNameForLevel(2000).isEmpty) // Kotlin assertNotNull
        XCTAssertEqual(99, LevelCatalog.episodeOf(2000))
    }
}
