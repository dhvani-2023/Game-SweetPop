import XCTest
@testable import SweetPop

final class MatchFinderTest: XCTestCase {

    func testFiveInRowMakesColourBomb() {
        let b = TestBoards.parse(
            "GBGBG",
            "BGBGB",
            "RRRRR"
        )
        let groups = MatchFinder.findGroups(b)
        XCTAssertEqual(1, groups.count)
        XCTAssertEqual(SpecialType.COLOR_BOMB, groups[0].special)
        XCTAssertEqual(Pos(2, 0), groups[0].specialPos)
    }

    func testLShapeMakesWrapped() {
        let b = TestBoards.parse(
            "RGB",
            "RBG",
            "RRR"
        )
        let groups = MatchFinder.findGroups(b)
        XCTAssertEqual(1, groups.count)
        XCTAssertEqual(SpecialType.WRAPPED, groups[0].special)
        XCTAssertEqual(5, groups[0].cells.count)
        // Placed at the intersection when no swap is involved.
        XCTAssertEqual(Pos(0, 0), groups[0].specialPos)
    }

    func testVerticalFourMakesStripedH() {
        let b = TestBoards.parse(
            "RGB",
            "RBG",
            "RGB",
            "RBG"
        )
        let groups = MatchFinder.findGroups(b)
        XCTAssertEqual(1, groups.count)
        XCTAssertEqual(SpecialType.STRIPED_H, groups[0].special)
    }

    func testHorizontalFourMakesStripedV() {
        let b = TestBoards.parse(
            "GBGB",
            "RRRR"
        )
        XCTAssertEqual(SpecialType.STRIPED_V, MatchFinder.findGroups(b)[0].special)
    }

    func testThreeInRowMakesNothing() {
        let b = TestBoards.parse(
            "GBG",
            "RRR"
        )
        let groups = MatchFinder.findGroups(b)
        XCTAssertEqual(1, groups.count)
        XCTAssertEqual(SpecialType.NONE, groups[0].special)
        XCTAssertNil(groups[0].specialPos)
    }

    func testSpecialPlacedOnSwappedIntoCell() {
        let b = TestBoards.parse(
            "GBGB",
            "RRRR"
        )
        let g = MatchFinder.findGroups(b, swappedInto: Pos(1, 0), other: Pos(1, 1))[0]
        XCTAssertEqual(Pos(1, 0), g.specialPos)
    }

    func testColourBombsNeverMatch() {
        let b = TestBoards.parse("R*RR")
        XCTAssertTrue(MatchFinder.findGroups(b).isEmpty)
    }

    func testHolesBreakRuns() {
        let b = TestBoards.parse("RR#R")
        XCTAssertFalse(MatchFinder.hasMatch(b))
    }

    func testValidMoveDetection() {
        let b = TestBoards.parse(
            "GRG",
            "RGR"
        )
        XCTAssertNotNil(MatchFinder.findValidMove(b))
        let none = TestBoards.parse(
            "RGB",
            "GBR"
        )
        XCTAssertNil(MatchFinder.findValidMove(none))
    }

    func testBombSwapIsAlwaysValid() {
        let b = TestBoards.parse("R*G")
        XCTAssertTrue(MatchFinder.isValidSwap(b, Pos(0, 0), Pos(1, 0)))
    }
}
