import Foundation
import GameKit

/// Cached access to generated levels plus episode naming (100 episodes × 20 levels).
enum LevelCatalog {
    static let LEVEL_COUNT = 2000
    static let LEVELS_PER_EPISODE = 20
    static let EPISODE_COUNT = LEVEL_COUNT / LEVELS_PER_EPISODE

    private static var cache = [Int: Level]()
    private static let lock = NSLock()

    private static let FIRST = [
        "Lollipop", "Gummy", "Caramel", "Toffee", "Marshmallow", "Bubblegum", "Cupcake", "Jellybean", "Licorice",
        "Praline", "Sherbet", "Fudge", "Taffy", "Cocoa", "Peppermint", "Sugar", "Honey", "Mochi", "Nougat",
        "Butterscotch", "Meringue", "Sprinkle", "Macaron", "Candyfloss", "Truffle",
    ]
    private static let SECOND = [
        "Lane", "Grove", "Canyon", "Town", "Meadow", "Bay", "Cove", "Jungle", "Lagoon", "Peaks", "Shore", "Falls",
        "Trail", "Cliffs", "Plains", "Summit",
    ]

    static func get(_ n: Int) -> Level {
        let k = n.coerceIn(1, LEVEL_COUNT)
        lock.lock()
        defer { lock.unlock() }
        if let l = cache[k] { return l }
        let l = LevelGenerator.generate(k)
        cache[k] = l
        return l
    }

    /// 0-based episode index for a level.
    static func episodeOf(_ level: Int) -> Int { (level.coerceIn(1, LEVEL_COUNT) - 1) / LEVELS_PER_EPISODE }

    static func episodeName(_ e: Int) -> String { FIRST[e % 25] + " " + SECOND[(e + (e / 25) * 5) % 16] }

    static func episodeNameForLevel(_ level: Int) -> String { episodeName(episodeOf(level)) }

    static func isTricky(_ level: Int) -> Bool { level % 10 == 0 }
}
