import XCTest
import GameKit
@testable import SweetPop

/// Parity with Android, proven against JVM dumps (Golden/source/GoldenDumpTest.kt, run as a JUnit test on a scratch
/// copy of the Android project). Golden/levels.json fingerprints every level 1…2000, Golden/traces.json records the
/// greedy bot of GameSimulationTest wave by wave for levels 1…60, Golden/bot.json holds the bot's results for the
/// whole GameSimulationTest sample (94/171 and 16/20 wins, as the JVM test prints).
/// Each line is rebuilt here with the same format and must match exactly.
final class GoldenTests: XCTestCase {

    // ------------------------------------------------------------------ golden files

    private static func goldenURL(_ name: String) -> URL? {
        let bundle = Bundle(for: GoldenTests.self)
        if let u = bundle.url(forResource: name, withExtension: "json") { return u }
        if let u = bundle.url(forResource: name, withExtension: "json", subdirectory: "Golden") { return u }
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden/\(name).json")
        return FileManager.default.fileExists(atPath: here.path) ? here : nil
    }

    private func loadJSON(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Self.goldenURL(name), "missing Golden/\(name).json")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // ------------------------------------------------------------------ tests

    func testLevelFingerprintsMatchAndroid() throws {
        let lines = try XCTUnwrap(try loadJSON("levels")["levels"] as? [String])
        XCTAssertEqual(LevelCatalog.LEVEL_COUNT, lines.count)
        var matched = 0
        var diffs = [String]()
        for n in 1...min(LevelCatalog.LEVEL_COUNT, lines.count) {
            let mine = Self.fingerprint(LevelGenerator.generate(n))
            if mine == lines[n - 1] {
                matched += 1
            } else if diffs.count < 5 {
                diffs.append("level \(n)\n android: \(lines[n - 1])\n ios:     \(mine)")
            }
        }
        print("Golden levels: \(matched)/\(lines.count) match Android")
        XCTAssertEqual(lines.count, matched, diffs.joined(separator: "\n"))
    }

    func testLevelCatalogServesGeneratedLevels() throws {
        let lines = try XCTUnwrap(try loadJSON("levels")["levels"] as? [String])
        for n in [1, 6, 7, 40, 41, 999, 2000] { XCTAssertEqual(lines[n - 1], Self.fingerprint(LevelCatalog.get(n))) }
        XCTAssertEqual(lines[0], Self.fingerprint(LevelCatalog.get(0)))
        XCTAssertEqual(lines[1999], Self.fingerprint(LevelCatalog.get(5000)))
    }

    func testEngineTracesMatchAndroid() throws {
        let traces = try XCTUnwrap(try loadJSON("traces")["traces"] as? [[String: Any]])
        XCTAssertEqual(60, traces.count)
        var matched = 0
        var lineCount = 0
        for t in traces {
            let n = try XCTUnwrap(t["n"] as? Int)
            let seed = try XCTUnwrap((t["seed"] as? NSNumber)?.int64Value)
            let golden = try XCTUnwrap(t["lines"] as? [String])
            var mine = [String]()
            _ = Self.play(n, seed, &mine)
            lineCount += golden.count
            if mine == golden {
                matched += 1
                continue
            }
            let common = min(mine.count, golden.count)
            let i = (0..<common).first { mine[$0] != golden[$0] } ?? common
            XCTFail("level \(n): trace diverges at line \(i) of \(golden.count) (ios has \(mine.count))\n"
                + " android: \(i < golden.count ? golden[i] : "<end>")\n"
                + " ios:     \(i < mine.count ? mine[i] : "<end>")")
        }
        print("Golden traces: \(matched)/\(traces.count) levels match Android (\(lineCount) lines)")
    }

    func testBotResultsMatchAndroid() throws {
        let lines = try XCTUnwrap(try loadJSON("bot")["bot"] as? [String])
        var matched = 0
        for l in lines {
            let parts = l.split(separator: "|").map(String.init)
            let n = try XCTUnwrap(Int(parts[0]))
            let seed = try XCTUnwrap(Int64(parts[1]))
            var sink: [String]? = nil
            let (won, score) = Self.play(n, seed, &sink)
            let mine = "\(n)|\(seed)|\(won)|\(score)"
            if mine == l { matched += 1 } else { XCTFail("bot game mismatch: android \(l) ios \(mine)") }
        }
        print("Golden bot games: \(matched)/\(lines.count) match Android")
    }

    // ------------------------------------------------------------------ formats (same as GoldenDumpTest.kt)

    private static let colorChars = Array("ROYGBPN")

    private static func colorChar(_ c: CandyColor) -> Character { colorChars[c.ordinal] }

    /// n|w|h|colors|moves|goal|target|collect|stars|difficultyBits|playable|jelly|frosting|initial
    static func fingerprint(_ l: Level) -> String {
        var s = "\(l.number)|\(l.width)|\(l.height)|\(l.colors)|\(l.moves)|\(l.goal.rawValue)|\(l.scoreTarget)|"
        s += l.collect.map { "\($0.color.rawValue):\($0.count)" }.joined(separator: ",") + "|"
        s += l.starScores.map { String($0) }.joined(separator: ",") + "|"
        s += "\(Kt.floatToIntBits(l.difficulty))|"
        s += l.playable.map { $0 ? "1" : "0" }.joined() + "|"
        s += l.jelly.map { String($0) }.joined() + "|"
        s += l.frosting.map { String($0) }.joined() + "|"
        s += l.initial.map { $0 < 0 ? "." : String($0) }.joined()
        return s
    }

    /// Two chars per cell (colour + special ordinal, ".." empty, "##" hole), then jelly and frosting digits.
    private static func boardString(_ b: Board) -> String {
        var s = ""
        for c in b.cells {
            if !c.playable {
                s += "##"
                continue
            }
            if let k = c.candy {
                s.append(colorChar(k.color))
                s += String(k.special.ordinal)
            } else {
                s += ".."
            }
        }
        s += "/"
        for c in b.cells { s += String(c.jelly) }
        s += "/"
        for c in b.cells { s += String(c.frosting) }
        return s
    }

    private static func idx(_ p: Pos, _ w: Int) -> Int { p.x + p.y * w }

    private static func milli(_ f: Float) -> Int { Kt.roundToInt(f * 1000) }

    private static func waveString(_ wv: Wave, _ w: Int) -> String {
        var s = "W\(wv.index)"
        s += "|c=" + wv.cleared.map { "\(idx($0.pos, w))\(colorChar($0.candy.color))\($0.candy.special.ordinal):\($0.candy.id)\($0.byBlast ? "*" : "")" }.joined(separator: ",")
        s += "|j=" + wv.jellyHits.map { "\(idx($0.pos, w)):\($0.layersBefore)" }.joined(separator: ",")
        s += "|f=" + wv.frostingHits.map { "\(idx($0.pos, w)):\($0.hpAfter)" }.joined(separator: ",")
        s += "|t=" + wv.triggers.map { t in
            "\(idx(t.pos, w)):\(t.special.ordinal):\(colorChar(t.color)):" + t.area.map { String(idx($0, w)) }.joined(separator: ".")
        }.joined(separator: ",")
        s += "|s=" + wv.scores.map { "\($0.points)@\(milli($0.x)):\(milli($0.y))\(colorChar($0.color))" }.joined(separator: ",")
        return s
    }

    private static func groupsString(_ gs: [MatchGroup], _ w: Int) -> String {
        gs.map { g in
            g.cells.map { String(idx($0, w)) }.joined(separator: ".")
                + ":\(colorChar(g.color)):\(g.special.ordinal):\(g.specialPos.map { idx($0, w) } ?? -1):\(g.runs.count)"
                + ":\(milli(g.centerX)):\(milli(g.centerY))"
        }.joined(separator: ";")
    }

    private static func comboString(_ s: ComboStart, _ w: Int) -> String {
        "C \(s.kind.rawValue) c=\(idx(s.center, w)) b=\(s.bombPos.map { idx($0, w) } ?? -1) col=\(colorChar(s.color)) "
            + "conv=" + s.converted.map { String(idx($0, w)) }.joined(separator: ".")
            + " area=" + s.area.map { String(idx($0, w)) }.joined(separator: ".")
            + " title=\(s.title ?? "null")"
    }

    private static func createdString(_ cs: [CreatedSpecial], _ w: Int) -> String {
        "S " + cs.map { "\(idx($0.pos, w)):\($0.candy.id):\(colorChar($0.candy.color))\($0.candy.special.ordinal)" }.joined(separator: ",")
    }

    /// Count, spawned count and a 31-hash (Kotlin Int wrap-around) over every move, in order.
    private static func movesString(_ moves: [Move]) -> String {
        var h: Int32 = 0
        func mix(_ v: Int) { h = h &* 31 &+ Int32(truncatingIfNeeded: v) }
        for m in moves {
            mix(m.candy.id)
            mix(milli(m.fromX))
            mix(milli(m.fromY))
            mix(m.toX)
            mix(m.toY)
            mix(m.spawned ? 1 : 0)
            mix(milli(m.distance))
        }
        return "n=\(moves.count) sp=\(moves.filter { $0.spawned }.count) h=\(h)"
    }

    // ------------------------------------------------------------------ GameSimulationTest's bot, recorded

    private static func emptyOpenCells(_ b: Board) -> Int { b.cells.reduce(0) { $0 + ($1.open && $1.candy == nil ? 1 : 0) } }

    private static func cascade(_ engine: BoardEngine, _ tracker: GoalTracker, _ board: Board, _ initial: [MatchGroup]?, _ start: Int, _ out: inout [String]?) {
        var c = start
        var groups = initial ?? MatchFinder.findGroups(board)
        var guardCount = 0
        while !groups.isEmpty {
            let g = guardCount
            guardCount += 1
            precondition(g < 200, "cascade runaway")
            out?.append("R c=\(c) g=\(groupsString(groups, board.width))")
            engine.beginMatches(groups, c)
            score(engine, tracker, board.width, &out)
            let created = engine.finishResolve()
            out?.append(createdString(created, board.width))
            let moves = engine.applyGravity()
            out?.append("G " + movesString(moves))
            c += 1
            groups = MatchFinder.findGroups(board)
        }
    }

    private static func score(_ engine: BoardEngine, _ tracker: GoalTracker, _ w: Int, _ out: inout [String]?) {
        for wv in engine.resolveAll() {
            out?.append(waveString(wv, w))
            for s in wv.scores { tracker.addScore(s.points) }
            for cc in wv.cleared {
                let slot = tracker.collectSlotFor(cc.candy.color)
                if slot >= 0 { tracker.collect(slot) }
            }
        }
    }

    private static func pickMove(_ board: Board, _ engine: BoardEngine, _ rnd: JavaRandom) -> PosPair? {
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

    private static func shuffleAndCascade(_ engine: BoardEngine, _ tracker: GoalTracker, _ board: Board, _ out: inout [String]?) {
        let moves = engine.shuffle()
        out?.append("X " + movesString(moves) + " b=" + boardString(board))
        cascade(engine, tracker, board, nil, 0, &out)
    }

    @discardableResult
    static func play(_ n: Int, _ seed: Int64, _ lines: inout [String]) -> (Bool, Int) {
        var out: [String]? = []
        let r = play(n, seed, &out)
        lines = out ?? []
        return r
    }

    static func play(_ n: Int, _ seed: Int64, _ out: inout [String]?) -> (Bool, Int) {
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
        out?.append("L n=\(n) seed=\(seed) id=\(id) empty=\(emptyOpenCells(board)) b=\(boardString(board))")
        var turn = 0
        while tracker.movesLeft > 0 {
            var picked = pickMove(board, engine, rnd)
            if picked == nil {
                out?.append("N")
                shuffleAndCascade(engine, tracker, board, &out)
                picked = pickMove(board, engine, rnd)
            }
            guard let m = picked else { break }
            let (a, b) = m
            engine.swap(a, b)
            tracker.useMove()
            let combo = engine.isComboSwap(a, b)
            out?.append("M \(turn) \(a.x),\(a.y)>\(b.x),\(b.y) combo=\(combo)")
            if combo {
                let start = engine.beginCombo(a, b)
                out?.append(comboString(start, board.width))
                score(engine, tracker, board.width, &out)
                // Engine calls stay outside `out?.append(...)`: optional chaining skips the argument when out is nil.
                let created = engine.finishResolve()
                out?.append(createdString(created, board.width))
                let moves = engine.applyGravity()
                out?.append("G " + movesString(moves))
                cascade(engine, tracker, board, nil, 1, &out)
            } else {
                let groups = MatchFinder.findGroups(board, swappedInto: b, other: a)
                precondition(!groups.isEmpty, "level \(n) bot picked a non-matching move")
                cascade(engine, tracker, board, groups, 0, &out)
            }
            tracker.refresh(board)
            out?.append(
                "T ml=\(tracker.movesLeft) mu=\(tracker.movesUsed) sc=\(tracker.score) j=\(tracker.jellyLeft) f=\(tracker.frostingLeft) "
                    + "c=\(tracker.collectRemaining.map { String($0) }.joined(separator: ",")) done=\(tracker.isGoalComplete) b=\(boardString(board))"
            )
            turn += 1
            if level.goal != .SCORE && tracker.isGoalComplete {
                out?.append("E won=true sc=\(tracker.score) stars=\(tracker.starsFor(tracker.score))")
                return (true, tracker.score)
            }
            if MatchFinder.findValidMove(board) == nil { shuffleAndCascade(engine, tracker, board, &out) }
        }
        out?.append("E won=\(tracker.isGoalComplete) sc=\(tracker.score) stars=\(tracker.starsFor(tracker.score))")
        return (tracker.isGoalComplete, tracker.score)
    }
}
