import Foundation
import GameKit

/// Score, moves, objectives and stars for one play of a level (spec 7.9).
final class GoalTracker {
    let level: Level
    private(set) var score: Int = 0
    var movesLeft: Int
    private(set) var movesUsed: Int = 0
    var collectRemaining: [Int]
    private(set) var jellyLeft: Int = 0
    private(set) var frostingLeft: Int = 0
    private var targetReachedOnce = false

    init(_ level: Level) {
        self.level = level
        self.movesLeft = level.moves
        self.collectRemaining = level.collect.map { $0.count }
    }

    func refresh(_ board: Board) {
        jellyLeft = board.countJellyCells()
        frostingLeft = board.countFrostingCells()
    }

    func useMove() {
        if movesLeft > 0 {
            movesLeft -= 1
            movesUsed += 1
        }
    }

    func addScore(_ points: Int) {
        score += points
    }

    /// Returns true exactly once: the first time a SCORE target is met.
    func consumeTargetReached() -> Bool {
        if targetReachedOnce || level.goal != .SCORE || score < level.scoreTarget { return false }
        targetReachedOnce = true
        return true
    }

    /// Index of the collect slot that wants this colour (and still needs some), or -1.
    func collectSlotFor(_ color: CandyColor) -> Int {
        if level.goal != .COLLECT { return -1 }
        for (i, t) in level.collect.enumerated() where t.color == color && collectRemaining[i] > 0 { return i }
        return -1
    }

    func collect(_ slot: Int) {
        if slot >= 0 && slot < collectRemaining.count && collectRemaining[slot] > 0 { collectRemaining[slot] -= 1 }
    }

    var isGoalComplete: Bool {
        switch level.goal {
        case .SCORE: return score >= level.scoreTarget
        case .JELLY: return jellyLeft == 0
        case .COLLECT: return collectRemaining.allSatisfy { $0 == 0 }
        case .FROSTING: return frostingLeft == 0
        }
    }

    /// Stars earned by a win with [finalScore]; a win is always at least one star.
    func starsFor(_ finalScore: Int) -> Int {
        let s = level.starScores
        if finalScore >= s[2] { return 3 }
        if finalScore >= s[1] { return 2 }
        return 1
    }

    /// "12 jelly left to clear" style summary for the lose dialog.
    func remainingSummary() -> String {
        switch level.goal {
        case .SCORE: return "\(GoalTracker.formatNumber((level.scoreTarget - score).coerceAtLeast(0))) points short"
        case .JELLY: return "\(jellyLeft) jelly left to clear"
        case .COLLECT: return "\(collectRemaining.reduce(0, +)) candies left to collect"
        case .FROSTING: return "\(frostingLeft) frosting left to break"
        }
    }

    static func goalDescription(_ level: Level) -> String {
        switch level.goal {
        case .SCORE: return "Score \(formatNumber(level.scoreTarget)) points!"
        case .JELLY: return "Clear all the jelly!"
        case .COLLECT: return "Collect the candies!"
        case .FROSTING: return "Break all the frosting!"
        }
    }

    static func formatNumber(_ n: Int) -> String {
        let s = Array(String(n))
        var sb = ""
        for (i, ch) in s.enumerated() {
            if i > 0 && (s.count - i) % 3 == 0 && ch != "-" { sb.append(",") }
            sb.append(ch)
        }
        return sb
    }
}
