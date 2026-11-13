import XCTest
import GameKit
@testable import SweetPop

/// Plays levels headlessly with a simple greedy bot through the same engine calls the view model makes,
/// checking invariants after every turn. Also prints win rates as a rough difficulty signal.
/// (JUnit assertions throw and end the test; here a failed invariant is recorded and the loop stops.)
final class GameSimulationTest: XCTestCase {

    private struct Result {
        let won: Bool
        let score: Int
    }

    private struct Abort: Error {}

    private func checkInvariants(_ b: Board, _ tag: String) throws {
        var failed = false
        b.forEachCell { x, y, c in
            if !c.playable && c.candy != nil { XCTFail("\(tag) candy on hole (\(x),\(y))"); failed = true }
            if c.frosting > 0 && c.candy != nil { XCTFail("\(tag) candy on frosting (\(x),\(y))"); failed = true }
            if !(0...2).contains(c.jelly) { XCTFail("\(tag) jelly range"); failed = true }
        }
        if failed { throw Abort() }
    }

    /// Open cells that stay empty must be unreachable (every neighbour feeding them is blocked).
    private func emptyOpenCells(_ b: Board) -> Int { b.cells.reduce(0) { $0 + ($1.open && $1.candy == nil ? 1 : 0) } }

    private func cascade(_ engine: BoardEngine, _ tracker: GoalTracker, _ board: Board, _ initial: [MatchGroup]?, _ start: Int) throws {
        var c = start
        var groups = initial ?? MatchFinder.findGroups(board)
        var guardCount = 0
        while !groups.isEmpty {
            let g = guardCount
            guardCount += 1
            if !(g < 200) { XCTFail("cascade runaway"); throw Abort() }
            engine.beginMatches(groups, c)
            score(engine, tracker)
            engine.finishResolve()
            engine.applyGravity()
            c += 1
            groups = MatchFinder.findGroups(board)
        }
    }

    private func score(_ engine: BoardEngine, _ tracker: GoalTracker) {
        for w in engine.resolveAll() {
            for s in w.scores { tracker.addScore(s.points) }
            for cc in w.cleared {
                let slot = tracker.collectSlotFor(cc.candy.color)
                if slot >= 0 { tracker.collect(slot) }
            }
        }
    }

    /// Prefers combos and specials, otherwise the move that clears the most candies right away.
    private func pickMove(_ board: Board, _ engine: BoardEngine, _ rnd: JavaRandom) -> PosPair? {
        let moves = MatchFinder.allValidMoves(board)
        if moves.isEmpty { return nil }
        var best = moves[rnd.nextInt(moves.count)]
        var bestScore = -1
        for m in moves {
            let s: Int
            if engine.isComboSwap(m.first, m.second) {
                s = 100
            } else {
                engine.swap(m.first, m.second)
                let g = MatchFinder.findGroups(board, swappedInto: m.second, other: m.first)
                engine.swap(m.first, m.second)
                s = g.reduce(0) { $0 + $1.cells.count + ($1.special != .NONE ? 10 : 0) }
            }
            if s > bestScore || (s == bestScore && rnd.nextBoolean()) {
                bestScore = s
                best = m
            }
        }
        return best
    }

    private func play(_ n: Int, _ seed: Int64) throws -> Result {
        let level = LevelGenerator.generate(n)
        var id = 1
        let board = Board.fromLevel(level) {
            let v = id
            id += 1
            return v
        }
        let rnd = JavaRandom(seed)
        let engine = BoardEngine(board, level.colors, rnd, startId: id)
        let tracker = GoalTracker(level)
        tracker.refresh(board)
        let tag = "level \(n)"
        let startEmpty = emptyOpenCells(board)
        while tracker.movesLeft > 0 {
            var picked = pickMove(board, engine, rnd)
            if picked == nil {
                engine.shuffle()
                try cascade(engine, tracker, board, nil, 0)
                picked = pickMove(board, engine, rnd)
            }
            guard let m = picked else { break }
            let (a, b) = m
            engine.swap(a, b)
            tracker.useMove()
            if engine.isComboSwap(a, b) {
                engine.beginCombo(a, b)
                score(engine, tracker)
                engine.finishResolve()
                engine.applyGravity()
                try cascade(engine, tracker, board, nil, 1)
            } else {
                let groups = MatchFinder.findGroups(board, swappedInto: b, other: a)
                if groups.isEmpty { XCTFail("\(tag) bot picked a non-matching move"); throw Abort() }
                try cascade(engine, tracker, board, groups, 0)
            }
            try checkInvariants(board, tag)
            if !(emptyOpenCells(board) <= startEmpty) { XCTFail("\(tag) holes appeared after refill"); throw Abort() }
            tracker.refresh(board)
            if level.goal != .SCORE && tracker.isGoalComplete { return Result(won: true, score: tracker.score) }
            if MatchFinder.findValidMove(board) == nil {
                engine.shuffle()
                try cascade(engine, tracker, board, nil, 0)
            }
        }
        return Result(won: tracker.isGoalComplete, score: tracker.score)
    }

    func testBotPlaysLevelsWithoutBreakingInvariants() throws {
        let sample = Array(1...120) + Array(stride(from: 121, through: 2000, by: 37))
        var wins = 0
        for n in sample {
            if try play(n, Int64(n) * 31).won { wins += 1 }
        }
        print("Greedy bot won \(wins) / \(sample.count) sampled levels")
        // Early levels should be very winnable even for a naive bot.
        var early = 0
        for n in 1...20 {
            if try play(n, Int64(n) * 7).won { early += 1 }
        }
        print("Greedy bot won \(early) / 20 of levels 1-20")
        XCTAssertTrue(early >= 12, "early levels too hard: \(early)/20")
    }
}
