import Foundation

/// Candy colours. NONE is used by colour bombs (and means "no colour").
/// `argb` is the Kotlin `Long` colour, typed `UInt32` so it feeds `Color(argb:)` directly.
enum CandyColor: String, CaseIterable {
    case RED, ORANGE, YELLOW, GREEN, BLUE, PURPLE, NONE

    var argb: UInt32 {
        switch self {
        case .RED: return 0xFFF52945
        case .ORANGE: return 0xFFFF8C1A
        case .YELLOW: return 0xFFFFD629
        case .GREEN: return 0xFF38CC52
        case .BLUE: return 0xFF338FFF
        case .PURPLE: return 0xFFAD4DF5
        case .NONE: return 0xFF5C301A
        }
    }

    /// Kotlin `ordinal` (declaration order).
    var ordinal: Int {
        switch self {
        case .RED: return 0
        case .ORANGE: return 1
        case .YELLOW: return 2
        case .GREEN: return 3
        case .BLUE: return 4
        case .PURPLE: return 5
        case .NONE: return 6
        }
    }

    /// Kotlin `CandyColor.entries`.
    static let entries: [CandyColor] = allCases

    static let PLAYABLE: [CandyColor] = [.RED, .ORANGE, .YELLOW, .GREEN, .BLUE, .PURPLE]
}

enum SpecialType: String, CaseIterable {
    case NONE, STRIPED_H, STRIPED_V, WRAPPED, COLOR_BOMB

    var isStriped: Bool { self == .STRIPED_H || self == .STRIPED_V }

    var ordinal: Int {
        switch self {
        case .NONE: return 0
        case .STRIPED_H: return 1
        case .STRIPED_V: return 2
        case .WRAPPED: return 3
        case .COLOR_BOMB: return 4
        }
    }

    static let entries: [SpecialType] = allCases
}

/// A candy on the board. The id is stable while it moves so animations can follow it.
final class Candy: Identifiable {
    let id: Int
    var color: CandyColor
    var special: SpecialType

    init(_ id: Int, _ color: CandyColor, _ special: SpecialType = .NONE) {
        self.id = id
        self.color = color
        self.special = special
    }

    var isBomb: Bool { special == .COLOR_BOMB }
    var isSpecial: Bool { special != .NONE }
    func snapshot() -> Candy { Candy(id, color, special) }
}

/// One grid cell. A cell with frosting > 0 never holds a candy.
final class Cell {
    let playable: Bool
    var jelly: Int
    var frosting: Int
    var candy: Candy?

    init(_ playable: Bool, jelly: Int = 0, frosting: Int = 0, candy: Candy? = nil) {
        self.playable = playable
        self.jelly = jelly
        self.frosting = frosting
        self.candy = candy
    }

    /// Can hold a candy right now (playable and not frosted).
    var open: Bool { playable && frosting == 0 }
}

/// Grid position: x = column (0 = left), y = row (0 = bottom).
struct Pos: Hashable {
    let x: Int
    let y: Int

    func neighbours4() -> [Pos] { [Pos(x - 1, y), Pos(x + 1, y), Pos(x, y - 1), Pos(x, y + 1)] }
    func isAdjacent(_ o: Pos) -> Bool { (abs(x - o.x) + abs(y - o.y)) == 1 }
}

extension Pos: CustomStringConvertible {
    init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    /// Kotlin data-class `toString()`.
    var description: String { "Pos(x=\(x), y=\(y))" }
}

/// Kotlin `Pair<Pos, Pos>` (a swap): a labelled tuple, so `.first`/`.second` and `let (a, b) = m` both work.
typealias PosPair = (first: Pos, second: Pos)

/// Insertion-ordered set: what Kotlin's `LinkedHashSet`, `setOf(...)` and `toSet()` give. Iteration follows
/// first insertion, which the engine relies on (wave order, score order, RNG order).
struct LinkedHashSet<Element: Hashable>: Sequence {
    private(set) var elements: [Element] = []
    private var members: Set<Element> = []

    init() {}

    init<S: Sequence>(_ items: S) where S.Element == Element {
        addAll(items)
    }

    var count: Int { elements.count }
    /// Kotlin `size`.
    var size: Int { elements.count }
    var isEmpty: Bool { elements.isEmpty }
    var first: Element? { elements.first }

    func contains(_ e: Element) -> Bool { members.contains(e) }

    /// Kotlin `add`: true if the element was not present.
    @discardableResult
    mutating func add(_ e: Element) -> Bool {
        if members.insert(e).inserted {
            elements.append(e)
            return true
        }
        return false
    }

    mutating func addAll<S: Sequence>(_ items: S) where S.Element == Element {
        for e in items { add(e) }
    }

    func toList() -> [Element] { elements }

    func makeIterator() -> IndexingIterator<[Element]> { elements.makeIterator() }
}

enum GoalType: String, CaseIterable {
    case SCORE, JELLY, COLLECT, FROSTING
}

struct CollectTarget: Equatable {
    let color: CandyColor
    let count: Int
}

extension CollectTarget {
    init(_ color: CandyColor, _ count: Int) {
        self.color = color
        self.count = count
    }
}

/// An immutable level definition produced by the generator. Arrays are indexed x + y * width.
final class Level {
    let number: Int
    let width: Int
    let height: Int
    let colors: Int
    let moves: Int
    let goal: GoalType
    let scoreTarget: Int
    let collect: [CollectTarget]
    let starScores: [Int]
    let playable: [Bool]
    let jelly: [Int]
    let frosting: [Int]
    /// Initial candy colour ordinal per cell, or -1 where there is no candy.
    let initial: [Int]
    let difficulty: Float

    init(
        number: Int, width: Int, height: Int, colors: Int, moves: Int, goal: GoalType, scoreTarget: Int,
        collect: [CollectTarget], starScores: [Int], playable: [Bool], jelly: [Int], frosting: [Int],
        initial: [Int], difficulty: Float
    ) {
        self.number = number
        self.width = width
        self.height = height
        self.colors = colors
        self.moves = moves
        self.goal = goal
        self.scoreTarget = scoreTarget
        self.collect = collect
        self.starScores = starScores
        self.playable = playable
        self.jelly = jelly
        self.frosting = frosting
        self.initial = initial
        self.difficulty = difficulty
    }

    func idx(_ x: Int, _ y: Int) -> Int { x + y * width }
    var palette: [CandyColor] { Array(CandyColor.PLAYABLE.prefix(colors)) }
    var isTricky: Bool { number % 10 == 0 }
}

/// Mutable board state.
final class Board {
    let width: Int
    let height: Int
    let cells: [Cell]

    init(_ width: Int, _ height: Int, _ cells: [Cell]) {
        self.width = width
        self.height = height
        self.cells = cells
    }

    @inline(__always)
    func inBounds(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < width && y >= 0 && y < height }

    subscript(_ x: Int, _ y: Int) -> Cell? { inBounds(x, y) ? cells[x + y * width] : nil }
    subscript(_ p: Pos) -> Cell? { self[p.x, p.y] }

    func candyAt(_ p: Pos) -> Candy? { self[p]?.candy }

    func forEachCell(_ block: (Int, Int, Cell) -> Void) {
        for y in 0..<height {
            for x in 0..<width { block(x, y, cells[x + y * width]) }
        }
    }

    func positions() -> [Pos] {
        var out = [Pos]()
        out.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width { out.append(Pos(x, y)) }
        }
        return out
    }

    /// Highest playable row in column x, or -1.
    func topPlayable(_ x: Int) -> Int {
        var y = height - 1
        while y >= 0 {
            if cells[x + y * width].playable { return y }
            y -= 1
        }
        return -1
    }

    func countJellyCells() -> Int { cells.reduce(0) { $0 + ($1.playable && $1.jelly > 0 ? 1 : 0) } }
    func countFrostingCells() -> Int { cells.reduce(0) { $0 + ($1.playable && $1.frosting > 0 ? 1 : 0) } }

    static func fromLevel(_ level: Level, _ nextId: () -> Int) -> Board {
        var cells = [Cell]()
        cells.reserveCapacity(level.width * level.height)
        for i in 0..<(level.width * level.height) {
            let c = Cell(level.playable[i], jelly: level.jelly[i], frosting: level.frosting[i])
            let col = level.initial[i]
            if c.open && col >= 0 { c.candy = Candy(nextId(), CandyColor.entries[col]) }
            cells.append(c)
        }
        return Board(level.width, level.height, cells)
    }
}
