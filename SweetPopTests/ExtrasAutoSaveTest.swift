import XCTest
import GameKit
@testable import SweetPop

/// iOS extras: the mid-level autosave restores a level exactly (cells, specials, jelly, frosting, tracker, stars),
/// through JSON and the FileStore file; the Lollipop Hammer engine helper; the view model's restore path.
final class ExtrasAutoSaveTest: XCTestCase {
    private var fileName = ""

    override func setUp() {
        super.setUp()
        fileName = "sweetpop-autosave-test-\(UUID().uuidString).json"
    }

    override func tearDown() {
        AutoSave.clear(name: fileName)
        super.tearDown()
    }

    private func level(where pick: (Level) -> Bool) -> Level {
        for n in 1...400 {
            let l = LevelCatalog.get(n)
            if pick(l) { return l }
        }
        fatalError("no level matches")
    }

    /// A board mid-level: specials of every kind, a hit jelly, a cracked frosting, an empty-colour bomb.
    private func playedState(_ l: Level) -> (Board, GoalTracker) {
        var id = 1
        let board = Board.fromLevel(l) {
            defer { id += 1 }
            return id
        }
        var specials: [SpecialType] = [.STRIPED_H, .STRIPED_V, .WRAPPED]
        var bombPlaced = false
        var jellyAdded = 0
        for c in board.cells where c.open {
            guard let k = c.candy else { continue }
            if let s = specials.first {
                k.special = s
                specials.removeFirst()
            } else if !bombPlaced {
                c.candy = Candy(k.id, .NONE, .COLOR_BOMB)
                bombPlaced = true
            } else if jellyAdded < 3 && c.jelly == 0 {
                c.jelly = jellyAdded % 2 + 1
                jellyAdded += 1
            }
        }
        if let f = board.cells.first(where: { $0.frosting > 1 }) { f.frosting -= 1 }
        let t = GoalTracker(l)
        t.addScore(4_321)
        for _ in 0..<3 { t.useMove() }
        if !t.collectRemaining.isEmpty { t.collectRemaining[0] = max(0, t.collectRemaining[0] - 4) }
        t.refresh(board)
        return (board, t)
    }

    private func assertSameCells(_ a: Board, _ b: Board, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.width, b.width, file: file, line: line)
        XCTAssertEqual(a.height, b.height, file: file, line: line)
        for i in a.cells.indices {
            let x = a.cells[i], y = b.cells[i]
            XCTAssertEqual(x.playable, y.playable, "cell \(i) playable", file: file, line: line)
            XCTAssertEqual(x.jelly, y.jelly, "cell \(i) jelly", file: file, line: line)
            XCTAssertEqual(x.frosting, y.frosting, "cell \(i) frosting", file: file, line: line)
            XCTAssertEqual(x.candy?.color, y.candy?.color, "cell \(i) colour", file: file, line: line)
            XCTAssertEqual(x.candy?.special, y.candy?.special, "cell \(i) special", file: file, line: line)
        }
    }

    func testSnapshotRoundTripRestoresTheBoardAndTrackerExactly() throws {
        for l in [level { $0.goal == .COLLECT }, level { $0.goal == .FROSTING }, level { $0.goal == .JELLY }] {
            let (board, tracker) = playedState(l)
            let snap = LevelSnapshot(level: l, board: board, tracker: tracker, starsLit: 2, movesMade: 3, freeMovesUsed: true, now: 42)
            XCTAssertTrue(snap.fits(l), "level \(l.number)")

            let data = try JSONEncoder().encode(snap)
            let back = try JSONDecoder().decode(LevelSnapshot.self, from: data)
            XCTAssertEqual(snap, back)

            var id = 100
            let rebuilt = back.makeBoard(l) {
                id += 1
                return id
            }
            assertSameCells(board, rebuilt)
            XCTAssertEqual(Set(rebuilt.cells.compactMap { $0.candy?.id }).count, rebuilt.cells.compactMap { $0.candy }.count) // fresh unique ids

            let t = GoalTracker(l)
            back.apply(to: t)
            t.refresh(rebuilt)
            XCTAssertEqual(tracker.score, t.score)
            XCTAssertEqual(tracker.movesLeft, t.movesLeft)
            XCTAssertEqual(tracker.movesUsed, t.movesUsed)
            XCTAssertEqual(tracker.collectRemaining, t.collectRemaining)
            XCTAssertEqual(tracker.jellyLeft, t.jellyLeft)
            XCTAssertEqual(tracker.frostingLeft, t.frostingLeft)
            XCTAssertEqual(tracker.isGoalComplete, t.isGoalComplete)
            XCTAssertEqual(2, back.starsLit)
            XCTAssertEqual(3, back.movesMade)
            XCTAssertTrue(back.freeMovesUsed)
        }
    }

    func testFileRoundTripAndClear() {
        let l = level { $0.goal == .FROSTING }
        let (board, tracker) = playedState(l)
        let snap = LevelSnapshot(level: l, board: board, tracker: tracker, starsLit: 1, movesMade: 3, freeMovesUsed: false)
        XCTAssertNil(AutoSave.load(name: fileName))
        AutoSave.write(snap, name: fileName)
        XCTAssertTrue(FileStore.exists(fileName))
        XCTAssertEqual(snap, AutoSave.load(name: fileName))
        AutoSave.clear(name: fileName)
        XCTAssertFalse(FileStore.exists(fileName))
        XCTAssertNil(AutoSave.load(name: fileName))
    }

    func testBrokenOrStaleSavesAreRejectedAndRemoved() throws {
        let l = level { $0.goal == .COLLECT }
        let (board, tracker) = playedState(l)
        let good = LevelSnapshot(level: l, board: board, tracker: tracker, starsLit: 0, movesMade: 1, freeMovesUsed: false)

        var wrongSize = good
        wrongSize.width += 1
        XCTAssertFalse(wrongSize.fits(l))
        var shortArray = good
        shortArray.color.removeLast()
        XCTAssertFalse(shortArray.fits(l))
        var otherLevel = good
        otherLevel.level += 1
        XCTAssertFalse(otherLevel.fits(l))
        var badColour = good
        badColour.color[badColour.color.firstIndex { $0 >= 0 }!] = 99
        XCTAssertFalse(badColour.fits(l))
        var candyOnFrosting = good
        let open = candyOnFrosting.color.firstIndex { $0 >= 0 }!
        candyOnFrosting.frosting[open] = 1
        XCTAssertFalse(candyOnFrosting.fits(l))
        var oldVersion = good
        oldVersion.version = 0
        XCTAssertFalse(oldVersion.fits(l))

        // A file that doesn't decode is deleted on load.
        try Data("{ not json".utf8).write(to: FileStore.url(fileName))
        XCTAssertNil(AutoSave.load(name: fileName))
        XCTAssertFalse(FileStore.exists(fileName))
        // So is one that no longer fits its level.
        AutoSave.write(wrongSize, name: fileName)
        XCTAssertNil(AutoSave.load(name: fileName))
        XCTAssertFalse(FileStore.exists(fileName))
    }

    func testReachedScoreTargetDoesNotAnnounceAgain() {
        let l = level { $0.goal == .SCORE }
        let (board, _) = playedState(l)
        let t = GoalTracker(l)
        t.addScore(l.scoreTarget + 10)
        XCTAssertTrue(t.consumeTargetReached())
        let snap = LevelSnapshot(level: l, board: board, tracker: t, starsLit: 1, movesMade: 2, freeMovesUsed: false)
        let restored = GoalTracker(l)
        snap.apply(to: restored)
        XCTAssertFalse(restored.consumeTargetReached())
        XCTAssertTrue(restored.isGoalComplete)
    }

    // ------------------------------------------------------------------ Lollipop Hammer engine helper

    func testHammerClearsOneCandyWithoutTouchingTheRng() {
        let b = TestBoards.parse(
            "GBGB",
            "BRBG",
            "YPYP"
        )
        b[1, 1]!.jelly = 2
        let rng = JavaRandom(Int64(7))
        let e = BoardEngine(b, 5, rng, startId: 1_000)
        XCTAssertTrue(e.beginHammer(Pos(1, 1)))
        let waves = e.resolveAll()
        XCTAssertEqual(1, waves.count)
        XCTAssertEqual([Pos(1, 1)], waves[0].cleared.map(\.pos))
        XCTAssertEqual(1, waves[0].jellyHits.count)
        XCTAssertEqual(1, b[1, 1]!.jelly)
        XCTAssertTrue(waves[0].triggers.isEmpty)
        XCTAssertNil(b[1, 1]!.candy)
        XCTAssertNotNil(b[0, 1]!.candy)
        XCTAssertTrue(e.finishResolve().isEmpty)
        XCTAssertEqual(JavaRandom(Int64(7)).nextInt(), rng.nextInt()) // nothing was drawn
        // Nothing to smash on an empty cell.
        XCTAssertFalse(e.beginHammer(Pos(1, 1)))
    }

    func testHammerFiresASpecial() {
        let b = TestBoards.parse(
            "GBGBG",
            "BGBGB",
            "YPROY"
        )
        b[2, 0]!.candy!.special = .STRIPED_H
        let e = BoardEngine(b, 5, JavaRandom(Int64(1)), startId: 1_000)
        XCTAssertTrue(e.beginHammer(Pos(2, 0)))
        let waves = e.resolveAll()
        XCTAssertEqual(2, waves.count)
        XCTAssertEqual(SpecialType.STRIPED_H, waves[0].triggers.first?.special)
        for x in 0..<5 { XCTAssertNil(b[x, 0]!.candy, "x=\(x)") }
        XCTAssertNotNil(b[2, 1]!.candy)
    }

    func testHammerCracksNeighbouringFrostingLikeAMatch() {
        let b = TestBoards.parse(
            "GBG",
            "BFB",
            "YRY"
        )
        let e = BoardEngine(b, 5, JavaRandom(Int64(1)), startId: 1_000)
        e.beginHammer(Pos(1, 0))
        let waves = e.resolveAll()
        XCTAssertEqual(1, waves[0].frostingHits.count)
        XCTAssertEqual(0, b[1, 1]!.frosting)
    }

    // ------------------------------------------------------------------ view model restore

    @MainActor
    func testGameViewModelRestoresTheSavedLevel() {
        let suite = "sweetpop-extras-vm-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = AppContainer(save: SaveRepository(store: Prefs(name: "sweetpop", defaults: defaults)))

        let l = level { $0.goal == .COLLECT }
        let (board, tracker) = playedState(l)
        // The view model's star markers for a non-score goal.
        let thresholds = [max(1, l.starScores[1] / 2), l.starScores[1], l.starScores[2]]
        let lit = thresholds.filter { tracker.score >= $0 }.count
        let snap = LevelSnapshot(level: l, board: board, tracker: tracker, starsLit: lit, movesMade: 3, freeMovesUsed: true, now: 7)
        container.extras.pendingRestore = snap

        let vm = GameViewModel(container: container, levelNumber: l.number)
        defer { vm.onCleared() }
        XCTAssertNil(container.extras.pendingRestore) // handed over once
        assertSameCells(board, vm.board)
        XCTAssertEqual(tracker.score, vm.score)
        XCTAssertEqual(tracker.movesLeft, vm.movesLeft)
        XCTAssertEqual(tracker.movesLeft, vm.tracker.movesLeft)
        XCTAssertEqual(tracker.movesUsed, vm.tracker.movesUsed)
        XCTAssertEqual(tracker.collectRemaining, vm.goalRemaining)
        XCTAssertEqual(thresholds, vm.starThresholds)
        XCTAssertEqual(lit, vm.starsLit)
        XCTAssertEqual(3, vm.movesMade)
        XCTAssertTrue(vm.extras.freeMovesUsed)
        XCTAssertTrue(vm.leavingCostsLife) // Android's life rules carry on

        // Saving again gives the same snapshot (apart from the time stamp).
        var again = vm.makeSnapshot()
        again.savedAtMillis = 7
        XCTAssertEqual(snap, again)

        // A different level ignores the pending restore and starts fresh.
        container.extras.pendingRestore = snap
        let other = GameViewModel(container: container, levelNumber: l.number + 1)
        defer { other.onCleared() }
        XCTAssertNotNil(container.extras.pendingRestore)
        XCTAssertEqual(0, other.score)
        XCTAssertEqual(LevelCatalog.get(l.number + 1).moves, other.movesLeft)
    }
}
