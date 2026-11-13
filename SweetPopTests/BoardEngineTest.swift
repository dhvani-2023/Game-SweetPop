import XCTest
import GameKit
@testable import SweetPop

final class BoardEngineTest: XCTestCase {
    private func engine(_ b: Board, colors: Int = 5) -> BoardEngine { BoardEngine(b, colors, JavaRandom(Int64(1)), startId: 10_000) }

    private func allFilled(_ b: Board) -> Bool { b.cells.allSatisfy { !$0.open || $0.candy != nil } }

    private func points(_ scores: [ScoreEvent]) -> Int { scores.reduce(0) { $0 + $1.points } }

    func testMatchClearsAndGravityRefills() {
        let b = TestBoards.parse(
            "GBGB",
            "BGBG",
            "RRRG"
        )
        let e = engine(b)
        e.beginMatches(MatchFinder.findGroups(b), 0)
        let waves = e.resolveAll()
        XCTAssertEqual(1, waves.count)
        XCTAssertEqual(3, waves[0].cleared.count)
        XCTAssertEqual((3 * 20) * 1, points(waves[0].scores))
        e.finishResolve()
        let moves = e.applyGravity()
        XCTAssertTrue(allFilled(b))
        XCTAssertEqual(9, moves.count) // 6 fell + 3 spawned
        XCTAssertEqual(3, moves.filter { $0.spawned }.count)
    }

    func testCascadeMultipliesScore() {
        let b = TestBoards.parse("GBGB", "RRRG")
        let e = engine(b)
        e.beginMatches(MatchFinder.findGroups(b), 2)
        XCTAssertEqual(3 * 20 * 3, points(e.resolveAll().flatMap { $0.scores }))
    }

    func testStripedHClearsWholeRow() {
        let b = TestBoards.parse(
            "GBGBGB",
            "RRROBP"
        )
        b[0, 0]!.candy!.special = .STRIPED_H
        let e = engine(b)
        e.beginMatches(MatchFinder.findGroups(b), 0)
        let waves = e.resolveAll()
        XCTAssertEqual(2, waves.count)
        XCTAssertEqual(1, waves[0].triggers.count) // Kotlin single()
        XCTAssertEqual(SpecialType.STRIPED_H, waves[0].triggers.first?.special)
        for x in 0..<6 { XCTAssertNil(b[x, 0]!.candy) }
        XCTAssertNotNil(b[0, 1]!.candy)
        // Blasted candies score 30 each.
        XCTAssertEqual(3 * 30, points(waves[1].scores))
    }

    func testWrappedClearsThreeByThree() {
        let b = TestBoards.parse(
            "GBGBG",
            "BGBGB",
            "GORRR",
            "BGBGB"
        )
        b[2, 1]!.candy!.special = .WRAPPED
        let e = engine(b)
        e.beginMatches(MatchFinder.findGroups(b), 0)
        e.resolveAll()
        for y in 0...2 {
            for x in 1...3 { XCTAssertNil(b[x, y]!.candy, "(\(x),\(y))") }
        }
        XCTAssertNotNil(b[0, 1]!.candy)
        XCTAssertNotNil(b[2, 3]!.candy)
    }

    func testMatchFourCreatesStripedAfterWaves() {
        let b = TestBoards.parse("GBGBG", "RRRRG")
        let e = engine(b)
        e.beginMatches(MatchFinder.findGroups(b, swappedInto: Pos(1, 0)), 0)
        e.resolveAll()
        let created = e.finishResolve()
        XCTAssertEqual(1, created.count)
        XCTAssertEqual(Pos(1, 0), created[0].pos)
        XCTAssertEqual(SpecialType.STRIPED_V, created[0].candy.special)
        XCTAssertEqual(CandyColor.RED, created[0].candy.color)
    }

    func testJellyDamagedEvenUnderEmptyBlastedCells() {
        let b = TestBoards.parse("GB.BG", "RRROB")
        b[4, 1]!.jelly = 0
        b[2, 1]!.jelly = 2
        b[0, 0]!.candy!.special = .STRIPED_V
        let e = engine(b)
        e.beginMatches(MatchFinder.findGroups(b), 0)
        e.resolveAll()
        // Column 0 striped blast doesn't reach x = 2, so jelly stays.
        XCTAssertEqual(2, b[2, 1]!.jelly)
        let b2 = TestBoards.parse("GB.BG", "RRROB")
        b2[2, 1]!.jelly = 2
        b2[2, 0]!.candy!.special = .STRIPED_V
        let e2 = engine(b2)
        e2.beginMatches(MatchFinder.findGroups(b2), 0)
        e2.resolveAll()
        XCTAssertEqual(1, b2[2, 1]!.jelly)
    }

    func testMatchesHitNeighbouringFrostingOnce() {
        let b = TestBoards.parse("FBGF", "RRRG")
        b[0, 1]!.frosting = 2
        let e = engine(b)
        e.beginMatches(MatchFinder.findGroups(b), 0)
        let waves = e.resolveAll()
        XCTAssertEqual(1, b[0, 1]!.frosting)
        XCTAssertEqual(1, b[3, 1]!.frosting) // not adjacent to the match
        XCTAssertEqual(1, waves[0].frostingHits.count)
    }

    func testBombBombClearsWholeBoard() {
        let b = TestBoards.parse("GBGB", "R**G", "BGBP")
        let e = engine(b)
        XCTAssertTrue(e.isComboSwap(Pos(1, 1), Pos(2, 1)))
        let start = e.beginCombo(Pos(1, 1), Pos(2, 1))
        XCTAssertEqual(ComboKind.BOMB_BOMB, start.kind)
        e.resolveAll()
        XCTAssertTrue(b.cells.allSatisfy { $0.candy == nil })
    }

    func testBombWithNormalClearsThatColour() {
        let b = TestBoards.parse("RBRB", "*RGG", "BGRP")
        let e = engine(b)
        let start = e.beginCombo(Pos(0, 1), Pos(1, 1))
        XCTAssertEqual(ComboKind.BOMB_NORMAL, start.kind)
        e.resolveAll()
        XCTAssertFalse(b.cells.contains { $0.candy?.color == .RED })
        XCTAssertEqual(CandyColor.BLUE, b[1, 2]!.candy!.color)
    }

    func testBombWithStripedConvertsAndFires() {
        let b = TestBoards.parse("GBGBG", "*RBGB", "BGBGR")
        b[1, 1]!.candy!.special = .STRIPED_H
        let e = engine(b)
        let start = e.beginCombo(Pos(0, 1), Pos(1, 1))
        XCTAssertEqual(ComboKind.BOMB_STRIPED, start.kind)
        XCTAssertEqual(1, start.converted.count) // the other red at (4,0)
        let waves = e.resolveAll()
        XCTAssertFalse(waves[0].triggers.isEmpty)
        // The converted red fired its line, so its row or column is clear.
        let rowClear = (0..<5).allSatisfy { b[$0, 0]!.candy == nil }
        let colClear = (0..<3).allSatisfy { b[4, $0]!.candy == nil }
        XCTAssertTrue(rowClear || colClear)
    }

    func testStripedStripedClearsRowAndColumn() {
        let b = TestBoards.parse("GBGBG", "BRPGB", "GBGBG")
        b[1, 1]!.candy!.special = .STRIPED_H
        b[2, 1]!.candy!.special = .STRIPED_V
        let e = engine(b)
        let start = e.beginCombo(Pos(1, 1), Pos(2, 1))
        XCTAssertEqual(ComboKind.STRIPED_STRIPED, start.kind)
        e.resolveAll()
        for x in 0..<5 { XCTAssertNil(b[x, 1]!.candy) }
        for y in 0..<3 { XCTAssertNil(b[2, y]!.candy) }
        XCTAssertNotNil(b[0, 0]!.candy)
    }

    func testWrappedWrappedIsFiveByFive() {
        let rows = (0..<7).map { r in r % 2 == 0 ? "GBGBGBG" : "BGBGBGB" }
        let b = TestBoards.parse(rows)
        b[3, 3]!.candy!.special = .WRAPPED
        b[4, 3]!.candy!.special = .WRAPPED
        let e = engine(b)
        XCTAssertEqual(ComboKind.WRAPPED_WRAPPED, e.beginCombo(Pos(3, 3), Pos(4, 3)).kind)
        e.resolveAll()
        for y in 1...5 {
            for x in 2...6 { XCTAssertNil(b[x, y]!.candy) }
        }
        XCTAssertNotNil(b[1, 3]!.candy)
        XCTAssertNotNil(b[4, 0]!.candy)
    }

    func testGravityRespectsHolesAndFrosting() {
        let b = TestBoards.parse(
            "GBG",
            "OFR",
            "..."
        )
        let e = engine(b)
        e.applyGravity()
        // Columns 0 and 2 fall and refill; the cell under the frosting is fed diagonally.
        XCTAssertTrue(allFilled(b))
        XCTAssertEqual(1, b[1, 1]!.frosting)
        XCTAssertNil(b[1, 1]!.candy)
    }

    func testGravityFallsThroughHoles() {
        let b = TestBoards.parse("G", "#", ".")
        engine(b).applyGravity()
        XCTAssertEqual(CandyColor.GREEN, b[0, 0]!.candy!.color)
        XCTAssertNotNil(b[0, 2]!.candy)
    }

    func testShuffleLeavesValidMoveAndNoMatches() {
        let b = TestBoards.parse(
            "RGBR",
            "GBRG",
            "BRGB",
            "RGBR"
        )
        let e = engine(b, colors: 3)
        e.shuffle()
        XCTAssertFalse(MatchFinder.hasMatch(b))
        XCTAssertNotNil(MatchFinder.findValidMove(b))
    }

    func testFireAllTriggersEverySpecial() {
        let b = TestBoards.parse("GBGB", "BGBG")
        b[0, 0]!.candy!.special = .STRIPED_H
        let e = engine(b)
        XCTAssertTrue(e.beginFireAll())
        e.resolveAll()
        for x in 0..<4 { XCTAssertNil(b[x, 0]!.candy) }
        XCTAssertFalse(engine(TestBoards.parse("GB")).beginFireAll())
    }
}
