import Foundation
import GameKit

// Pure rules of the iOS extras (no UI, no storage): coin rewards, boosters, daily spin, login gift, episode chest.
// Unit-tested in SweetPopTests/ExtrasEconomyTest.swift.

/// The three boosters. Raw values are the save-key suffixes (`booster_HAMMER`, `booster_SWAP`, `booster_MOVES`).
enum Booster: String, CaseIterable, Codable {
    case HAMMER, SWAP, MOVES

    /// Shop price in coins (bought one at a time, only when none are left).
    var price: Int {
        switch self {
        case .HAMMER: return 100
        case .SWAP: return 80
        case .MOVES: return 150
        }
    }

    var title: String {
        switch self {
        case .HAMMER: return "Lollipop Hammer"
        case .SWAP: return "Free Swap"
        case .MOVES: return "+5 Moves"
        }
    }

    /// Short name for small labels (reward rows, wheel).
    var shortName: String {
        switch self {
        case .HAMMER: return "Hammer"
        case .SWAP: return "Free Swap"
        case .MOVES: return "+5 Moves"
        }
    }

    /// What it does (shop dialog).
    var blurb: String {
        switch self {
        case .HAMMER: return "Tap any candy to smash it. Specials fire!"
        case .SWAP: return "Swap any two neighbouring candies, even without a match. Uses no move."
        case .MOVES: return "Five extra moves for this level."
        }
    }

    /// Shown while the booster waits for its target (Hammer and Free Swap only).
    var armedHint: String {
        switch self {
        case .HAMMER: return "Tap a candy to smash it!"
        case .SWAP: return "Swap any two candies!"
        case .MOVES: return ""
        }
    }

    var saveKey: String { "booster_" + rawValue }
}

enum Economy {
    /// Every win: 20 coins + 10 per star; Sweet Frenzy adds 2 per move left when it starts.
    static let WIN_BASE = 20
    static let PER_STAR = 10
    static let PER_FRENZY_MOVE = 2
    /// New players (and a progress reset) start with 2 of each booster.
    static let START_BOOSTERS = 2
    /// Moves added by the +5 Moves booster / Lose-dialog offer.
    static let EXTRA_MOVES = 5

    /// Coins for winning with [stars] (1…3) and [frenzyMoves] moves left when Sweet Frenzy started.
    static func winCoins(stars: Int, frenzyMoves: Int) -> Int {
        WIN_BASE + PER_STAR * stars.coerceIn(0, 3) + PER_FRENZY_MOVE * frenzyMoves.coerceAtLeast(0)
    }
}

/// The once-a-day prize wheel: 8 segments clockwise from the top.
enum DailySpin {
    enum Prize: Equatable {
        case coins(Int)
        case booster(Booster)
        case life
    }

    struct Segment {
        let prize: Prize
        /// Relative chance out of the weights' sum (100).
        let weight: Int
        /// Wedge colour (Android-style ARGB).
        let argb: UInt32
    }

    static let segments: [Segment] = [
        Segment(prize: .coins(25), weight: 24, argb: 0xFFFF6FB1),
        Segment(prize: .booster(.HAMMER), weight: 10, argb: 0xFF8B4DFF),
        Segment(prize: .coins(50), weight: 20, argb: 0xFF35B6FF),
        Segment(prize: .booster(.SWAP), weight: 12, argb: 0xFFFFB020),
        Segment(prize: .coins(100), weight: 12, argb: 0xFF2BCB72),
        Segment(prize: .booster(.MOVES), weight: 10, argb: 0xFFFF7A1A),
        Segment(prize: .coins(200), weight: 4, argb: 0xFFFF3D8B),
        Segment(prize: .life, weight: 8, argb: 0xFF26C6DA),
    ]

    static var count: Int { segments.count }

    /// Degrees per segment.
    static var sweep: Double { 360 / Double(segments.count) }

    /// One spin per local calendar day ([spinDay] = epoch day of the last spin, −1 = never). A clock set back
    /// before the last spin does not give another one.
    static func isAvailable(spinDay: Int, today: Int) -> Bool { spinDay < today }

    /// Winning segment for a uniform [roll] in 0..<1. With full lives the life segment can't win.
    static func pick(roll: Double, livesFull: Bool) -> Int {
        var total = 0
        for s in segments where !(livesFull && s.prize == .life) { total += s.weight }
        var x = roll.coerceIn(0, 0.999_999_999) * Double(total)
        var last = 0
        for (i, s) in segments.enumerated() {
            if livesFull && s.prize == .life { continue }
            last = i
            if x < Double(s.weight) { return i }
            x -= Double(s.weight)
        }
        return last
    }

    static func label(_ p: Prize) -> String {
        switch p {
        case .coins(let n): return "\(n) coins"
        case .booster(let b): return b.title
        case .life: return "1 life"
        }
    }
}

/// 7-day login calendar: a streak that grows by one each consecutive day, wraps after day 7 and resets to day 1
/// when a day is missed.
enum LoginGift {
    static let DAYS = 7
    static let coins = [20, 30, 40, 60, 80, 100, 200]

    /// The gift day (1…7) to claim on [today], or nil if today's gift was already claimed.
    /// [lastDay] = epoch day of the last claim (−1 = never), [lastStreak] = that claim's gift day (0 = none).
    static func dayToClaim(lastDay: Int, lastStreak: Int, today: Int) -> Int? {
        if lastDay >= today { return nil }
        if lastDay == today - 1 && (1...DAYS).contains(lastStreak) { return lastStreak % DAYS + 1 }
        return 1
    }

    static func coins(day: Int) -> Int { coins[(day - 1).coerceIn(0, DAYS - 1)] }

    /// Day 7 also gives one of each booster.
    static func boostersPerKind(day: Int) -> Int { day == DAYS ? 1 : 0 }
}

/// What the episode chest gave (persisted at the win; the dialog only reveals it).
struct ChestReward: Equatable {
    let episode: Int
    let coins: Int
    let booster: Booster
}

/// End-of-episode chest: completing level 20, 40, 60… gives 100 coins + 1 random booster, once per episode.
enum EpisodeChest {
    static let COINS = 100

    /// The episode (1-based) whose last level is [level], or nil.
    static func episodeEnding(at level: Int) -> Int? {
        let per = LevelCatalog.LEVELS_PER_EPISODE
        return level > 0 && level % per == 0 ? level / per : nil
    }

    /// [claimed] = the last episode whose chest was given (episodes finish in order, so a replay never pays twice).
    static func isDue(level: Int, claimed: Int) -> Bool {
        guard let e = episodeEnding(at: level) else { return false }
        return e > claimed
    }
}
