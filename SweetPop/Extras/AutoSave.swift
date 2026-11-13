import Foundation
import GameKit

/**
 * A level in progress, written to a FileStore JSON file when the app goes to the background mid-level, so the
 * level survives iOS closing the app. Holds everything the board and HUD need to continue exactly: every cell
 * (candy colour + special, jelly layers, frosting hp), the tracker (score, moves left / used, collect counts),
 * the lit stars and the level number. The refill RNG is not saved: a restored level draws new candies from a
 * fresh seed (level generation is untouched).
 */
struct LevelSnapshot: Codable, Equatable {
    static let VERSION = 1

    var version: Int = LevelSnapshot.VERSION
    var level: Int
    var width: Int
    var height: Int
    /// Per cell, indexed x + y * width like `Level` arrays.
    var jelly: [Int]
    var frosting: [Int]
    /// `CandyColor.ordinal`, −1 = no candy.
    var color: [Int]
    /// `SpecialType.ordinal` (0 when there is no candy).
    var special: [Int]
    var score: Int
    var movesLeft: Int
    var movesUsed: Int
    var collectRemaining: [Int]
    var starsLit: Int
    /// Moves made this attempt (leaving costs a life once this is > 0, like Android).
    var movesMade: Int
    /// The free Lose-dialog "+5 Moves" was already used this attempt.
    var freeMovesUsed: Bool
    var savedAtMillis: Int64
}

extension LevelSnapshot {
    /// Captures a settled board (call between turns, never mid-cascade).
    init(
        level: Level, board: Board, tracker: GoalTracker, starsLit: Int, movesMade: Int, freeMovesUsed: Bool,
        now: Int64 = Days.nowMillis()
    ) {
        let n = board.width * board.height
        var jelly = [Int](repeating: 0, count: n)
        var frosting = [Int](repeating: 0, count: n)
        var color = [Int](repeating: -1, count: n)
        var special = [Int](repeating: 0, count: n)
        for i in 0..<n {
            let c = board.cells[i]
            jelly[i] = c.jelly
            frosting[i] = c.frosting
            if let k = c.candy {
                color[i] = k.color.ordinal
                special[i] = k.special.ordinal
            }
        }
        self.init(
            level: level.number, width: board.width, height: board.height, jelly: jelly, frosting: frosting,
            color: color, special: special, score: tracker.score, movesLeft: tracker.movesLeft, movesUsed: tracker.movesUsed,
            collectRemaining: tracker.collectRemaining, starsLit: starsLit, movesMade: movesMade,
            freeMovesUsed: freeMovesUsed, savedAtMillis: now
        )
    }

    /// True when this snapshot belongs to [lvl] (same size and cell mask) and every value is in range.
    func fits(_ lvl: Level) -> Bool {
        guard version == Self.VERSION, level == lvl.number, width == lvl.width, height == lvl.height else { return false }
        let n = width * height
        guard jelly.count == n, frosting.count == n, color.count == n, special.count == n else { return false }
        guard collectRemaining.count == lvl.collect.count, collectRemaining.allSatisfy({ $0 >= 0 }) else { return false }
        guard score >= 0, (0...10_000).contains(movesLeft), (0...10_000).contains(movesUsed), movesMade >= 0,
              (0...3).contains(starsLit) else { return false }
        for i in 0..<n {
            if !lvl.playable[i] {
                if color[i] >= 0 || jelly[i] != 0 || frosting[i] != 0 { return false }
                continue
            }
            if !(0...2).contains(jelly[i]) || !(0...9).contains(frosting[i]) { return false }
            if !(-1..<CandyColor.entries.count).contains(color[i]) || !(0..<SpecialType.entries.count).contains(special[i]) { return false }
            if frosting[i] > 0 && color[i] >= 0 { return false }
        }
        return true
    }

    /// Rebuilds the board; candies get fresh ids from [nextId] (row by row, like `Board.fromLevel`).
    func makeBoard(_ lvl: Level, _ nextId: () -> Int) -> Board {
        var cells = [Cell]()
        cells.reserveCapacity(width * height)
        for i in 0..<(width * height) {
            let c = Cell(lvl.playable[i], jelly: jelly[i], frosting: frosting[i])
            if color[i] >= 0 {
                c.candy = Candy(nextId(), CandyColor.entries[color[i]], SpecialType.entries[special[i]])
            }
            cells.append(c)
        }
        return Board(width, height, cells)
    }

    /// Puts score, moves and collect counts into a fresh tracker for the same level (jelly / frosting counts
    /// come from `refresh(board)`).
    func apply(to tracker: GoalTracker) {
        tracker.addScore(score)
        // A reached SCORE target already showed its banner: consume the one-shot flag.
        _ = tracker.consumeTargetReached()
        tracker.movesLeft = movesUsed
        for _ in 0..<movesUsed { tracker.useMove() }
        tracker.movesLeft = movesLeft
        tracker.collectRemaining = collectRemaining
    }
}

/// The autosave file in Application Support (GameKit `FileStore`).
enum AutoSave {
    static let defaultName = "sweetpop_level_autosave.json"

    static func write(_ s: LevelSnapshot, name: String = defaultName) { FileStore.write(s, to: name) }

    static func read(name: String = defaultName) -> LevelSnapshot? { FileStore.read(LevelSnapshot.self, from: name) }

    /// The saved level, if it still fits its level definition; a stale or broken file is removed.
    static func load(name: String = defaultName) -> LevelSnapshot? {
        guard FileStore.exists(name) else { return nil }
        guard let s = read(name: name), (1...LEVEL_COUNT).contains(s.level), s.fits(LevelCatalog.get(s.level)) else {
            clear(name: name)
            return nil
        }
        return s
    }

    static func clear(name: String = defaultName) {
        if FileStore.exists(name) { FileStore.delete(name) }
    }
}
