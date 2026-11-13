import Foundation

/// A straight line of ≥ 3 same-colour candies. Cells are ordered left→right or bottom→top.
struct Run {
    let cells: [Pos]
    let horizontal: Bool
    let color: CandyColor

    init(_ cells: [Pos], _ horizontal: Bool, _ color: CandyColor) {
        self.cells = cells
        self.horizontal = horizontal
        self.color = color
    }

    var length: Int { cells.count }
}

/// Runs that share cells, merged. [special] is what the group creates and [specialPos] where.
/// `cells` keeps Kotlin's LinkedHashSet order (run by run, cell by cell).
struct MatchGroup {
    let cells: LinkedHashSet<Pos>
    let color: CandyColor
    let runs: [Run]
    let special: SpecialType
    let specialPos: Pos?

    init(_ cells: LinkedHashSet<Pos>, _ color: CandyColor, _ runs: [Run], _ special: SpecialType, _ specialPos: Pos?) {
        self.cells = cells
        self.color = color
        self.runs = runs
        self.special = special
        self.specialPos = specialPos
    }

    var centerX: Float { Float(cells.reduce(0) { $0 + $1.x }) / Float(cells.count) }
    var centerY: Float { Float(cells.reduce(0) { $0 + $1.y }) / Float(cells.count) }
}

/// Pure match detection and special-creation rules (spec 7.4).
enum MatchFinder {
    /// Colour a cell contributes to matches, or null (empty, frosted, colour bomb).
    static func matchColor(_ board: Board, _ x: Int, _ y: Int) -> CandyColor? {
        guard let c = board[x, y] else { return nil }
        if !c.open { return nil }
        guard let candy = c.candy else { return nil }
        if candy.isBomb || candy.color == .NONE { return nil }
        return candy.color
    }

    static func findRuns(_ board: Board) -> [Run] {
        var runs = [Run]()
        for y in 0..<board.height {
            var x = 0
            while x < board.width {
                guard let col = matchColor(board, x, y) else { x += 1; continue }
                var e = x + 1
                while e < board.width && matchColor(board, e, y) == col { e += 1 }
                if e - x >= 3 { runs.append(Run((x..<e).map { Pos($0, y) }, true, col)) }
                x = e
            }
        }
        for x in 0..<board.width {
            var y = 0
            while y < board.height {
                guard let col = matchColor(board, x, y) else { y += 1; continue }
                var e = y + 1
                while e < board.height && matchColor(board, x, e) == col { e += 1 }
                if e - y >= 3 { runs.append(Run((y..<e).map { Pos(x, $0) }, false, col)) }
                y = e
            }
        }
        return runs
    }

    static func hasMatch(_ board: Board) -> Bool { !findRuns(board).isEmpty }

    /// Groups of matched candies with the special each creates.
    /// [swappedInto] is the cell the player's candy moved into; [other] the other swapped cell.
    static func findGroups(_ board: Board, swappedInto: Pos? = nil, other: Pos? = nil) -> [MatchGroup] {
        let runs = findRuns(board)
        if runs.isEmpty { return [] }
        // Union runs that share a cell.
        var parent = Array(0..<runs.count)
        func find(_ i: Int) -> Int {
            var r = i
            while parent[r] != r { r = parent[r] }
            var c = i
            while parent[c] != r {
                let n = parent[c]
                parent[c] = r
                c = n
            }
            return r
        }
        var owner = [Pos: Int]()
        for (i, run) in runs.enumerated() {
            for p in run.cells {
                if let o = owner[p] {
                    let ri = find(i)
                    let ro = find(o)
                    parent[ri] = ro
                } else {
                    owner[p] = i
                }
            }
        }
        // LinkedHashMap<root, runs>: groups in order of their first run.
        var rootOrder = [Int]()
        var byRoot = [Int: [Run]]()
        for (i, run) in runs.enumerated() {
            let r = find(i)
            if byRoot[r] == nil {
                rootOrder.append(r)
                byRoot[r] = [run]
            } else {
                byRoot[r]!.append(run)
            }
        }
        return rootOrder.map { buildGroup(byRoot[$0]!, swappedInto, other) }
    }

    private static func buildGroup(_ runs: [Run], _ swappedInto: Pos?, _ other: Pos?) -> MatchGroup {
        var cells = LinkedHashSet<Pos>()
        for r in runs { cells.addAll(r.cells) }
        // Kotlin maxBy: the first run with the greatest length wins ties.
        var longest = runs[0]
        for r in runs.dropFirst() where longest.length < r.length { longest = r }
        let hasH = runs.contains { $0.horizontal }
        let hasV = runs.contains { !$0.horizontal }
        let special: SpecialType
        if longest.length >= 5 {
            special = .COLOR_BOMB
        } else if hasH && hasV {
            special = .WRAPPED
        } else if longest.length == 4 {
            special = longest.horizontal ? .STRIPED_V : .STRIPED_H
        } else {
            special = .NONE
        }
        let pos: Pos?
        if special == .NONE {
            pos = nil
        } else if let s = swappedInto, cells.contains(s) {
            pos = s
        } else if let o = other, cells.contains(o) {
            pos = o
        } else if special == .WRAPPED {
            pos = intersection(runs) ?? longest.cells[longest.length / 2]
        } else {
            pos = longest.cells[longest.length / 2]
        }
        return MatchGroup(cells, longest.color, runs, special, pos)
    }

    private static func intersection(_ runs: [Run]) -> Pos? {
        var h = Set<Pos>()
        for r in runs where r.horizontal { h.formUnion(r.cells) }
        for r in runs where !r.horizontal {
            for p in r.cells where h.contains(p) { return p }
        }
        return nil
    }

    /// True if a horizontal or vertical run of ≥ 3 passes through (x, y).
    static func matchAt(_ board: Board, _ x: Int, _ y: Int) -> Bool {
        guard let col = matchColor(board, x, y) else { return false }
        var l = x
        while matchColor(board, l - 1, y) == col { l -= 1 }
        var r = x
        while matchColor(board, r + 1, y) == col { r += 1 }
        if r - l + 1 >= 3 { return true }
        var b = y
        while matchColor(board, x, b - 1) == col { b -= 1 }
        var t = y
        while matchColor(board, x, t + 1) == col { t += 1 }
        return t - b + 1 >= 3
    }

    /// Whether swapping a and b is a legal move (makes a match, or is a bomb/special combo).
    static func isValidSwap(_ board: Board, _ a: Pos, _ b: Pos) -> Bool {
        guard let ca = board[a], let cb = board[b], let x = ca.candy, let y = cb.candy else { return false }
        if !ca.open || !cb.open { return false }
        if x.isBomb || y.isBomb { return true }
        if x.isSpecial && y.isSpecial { return true }
        ca.candy = y
        cb.candy = x
        let ok = matchAt(board, a.x, a.y) || matchAt(board, b.x, b.y)
        ca.candy = x
        cb.candy = y
        return ok
    }

    static func allValidMoves(_ board: Board) -> [PosPair] {
        var out = [PosPair]()
        for y in 0..<board.height {
            for x in 0..<board.width {
                let a = Pos(x, y)
                let r = Pos(x + 1, y)
                let u = Pos(x, y + 1)
                if board.inBounds(r.x, r.y) && isValidSwap(board, a, r) { out.append((first: a, second: r)) }
                if board.inBounds(u.x, u.y) && isValidSwap(board, a, u) { out.append((first: a, second: u)) }
            }
        }
        return out
    }

    static func findValidMove(_ board: Board) -> PosPair? {
        for y in 0..<board.height {
            for x in 0..<board.width {
                let a = Pos(x, y)
                if x + 1 < board.width && isValidSwap(board, a, Pos(x + 1, y)) { return (first: a, second: Pos(x + 1, y)) }
                if y + 1 < board.height && isValidSwap(board, a, Pos(x, y + 1)) { return (first: a, second: Pos(x, y + 1)) }
            }
        }
        return nil
    }
}
