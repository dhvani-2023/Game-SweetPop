import Foundation
import GameKit

/// A candy removed during a wave.
struct ClearedCandy {
    let candy: Candy
    let pos: Pos
    let byBlast: Bool
}

/// A special that fired during a wave and the cells its effect covers.
struct Trigger {
    let pos: Pos
    let special: SpecialType
    let color: CandyColor
    let area: [Pos]
}

struct JellyHit {
    let pos: Pos
    let layersBefore: Int
}

struct FrostingHit {
    let pos: Pos
    let hpAfter: Int
}

/// Points at a position in cell coordinates (x, y may be fractional for group centres).
struct ScoreEvent {
    let points: Int
    let x: Float
    let y: Float
    let color: CandyColor
}

/// One step of a chain reaction.
struct Wave {
    let index: Int
    let cleared: [ClearedCandy]
    let jellyHits: [JellyHit]
    let frostingHits: [FrostingHit]
    let triggers: [Trigger]
    let scores: [ScoreEvent]
}

struct CreatedSpecial {
    let pos: Pos
    let candy: Candy
}

/// A candy moved by gravity, a shuffle or a swap; from is in (possibly off-board) cell coordinates.
struct Move {
    let candy: Candy
    let fromX: Float
    let fromY: Float
    let toX: Int
    let toY: Int
    let spawned: Bool

    var distance: Float { Kt.max(abs(fromY - Float(toY)), abs(fromX - Float(toX))) }
}

enum ComboKind: String, CaseIterable {
    case BOMB_BOMB, BOMB_NORMAL, BOMB_STRIPED, BOMB_WRAPPED, STRIPED_STRIPED, STRIPED_WRAPPED, WRAPPED_WRAPPED
}

/// What a special-swap combo does before its waves start.
struct ComboStart {
    let kind: ComboKind
    let center: Pos
    let bombPos: Pos?
    let color: CandyColor
    /// Candies turned into specials by a bomb combo (already changed on the board).
    let converted: [Pos]
    let area: [Pos]

    var title: String? {
        switch kind {
        case .BOMB_BOMB: return "Sugar Storm!"
        case .BOMB_STRIPED, .BOMB_WRAPPED: return "Sweet Combo!"
        case .STRIPED_WRAPPED: return "Candy Cross!"
        case .WRAPPED_WRAPPED: return "Big Pop!"
        default: return nil
        }
    }
}

/// Pure board rules: swaps, wave-by-wave clearing with chain reactions, specials, combos, gravity and shuffle.
/// Resolution is incremental so the UI can animate each wave: begin…() → nextWave() until nil → finishResolve().
/// `rng` is shared with whoever else draws from it (the Kotlin bot does), so every call keeps Kotlin's order.
final class BoardEngine {
    let board: Board
    private let colors: Int
    private let rng: JavaRandom
    private var idCounter: Int

    init(_ board: Board, _ colors: Int, _ rng: JavaRandom, startId: Int = 1) {
        self.board = board
        self.colors = colors
        self.rng = rng
        self.idCounter = startId
    }

    convenience init(board: Board, colors: Int, rng: JavaRandom, startId: Int = 1) {
        self.init(board, colors, rng, startId: startId)
    }

    /// Kotlin `idCounter++`.
    func newId() -> Int {
        let v = idCounter
        idCounter += 1
        return v
    }

    func randomColor() -> CandyColor { CandyColor.PLAYABLE[rng.nextInt(colors)] }

    // ------------------------------------------------------------------ swap

    func swap(_ a: Pos, _ b: Pos) {
        let ca = board[a]!
        let cb = board[b]!
        let t = ca.candy
        ca.candy = cb.candy
        cb.candy = t
    }

    func canSwap(_ a: Pos, _ b: Pos) -> Bool {
        if !a.isAdjacent(b) { return false }
        guard let ca = board[a], let cb = board[b] else { return false }
        return ca.open && cb.open && ca.candy != nil && cb.candy != nil
    }

    /// True when the swapped pair forms a combo: either is a colour bomb, or both are specials.
    func isComboSwap(_ a: Pos, _ b: Pos) -> Bool {
        guard let x = board.candyAt(a), let y = board.candyAt(b) else { return false }
        return x.isBomb || y.isBomb || (x.isSpecial && y.isSpecial)
    }

    // ------------------------------------------------------------------ resolve state

    private struct PendingSpecial {
        let pos: Pos
        let color: CandyColor
        let special: SpecialType
    }

    private final class Resolve {
        var current: LinkedHashSet<Pos>
        let cascade: Int
        let consumed: Set<Pos>
        let pending: [PendingSpecial]
        let groupScores: [ScoreEvent]
        let neighbourFrost: LinkedHashSet<Pos>
        /// Wave-0 cells are blasts (combo / frenzy) rather than a match.
        let blastStart: Bool
        let comboPoints: Bool
        var processed = Set<Pos>()
        var index = 0

        init(_ current: LinkedHashSet<Pos>, _ cascade: Int, _ consumed: Set<Pos>, _ pending: [PendingSpecial],
             _ groupScores: [ScoreEvent], _ neighbourFrost: LinkedHashSet<Pos>, blastStart: Bool, comboPoints: Bool) {
            self.current = current
            self.cascade = cascade
            self.consumed = consumed
            self.pending = pending
            self.groupScores = groupScores
            self.neighbourFrost = neighbourFrost
            self.blastStart = blastStart
            self.comboPoints = comboPoints
        }
    }

    private var resolve: Resolve?

    var isResolving: Bool { resolve != nil }

    /// Whether another wave is queued after the one just processed.
    var hasNextWave: Bool { resolve?.current.isEmpty == false }

    /// Starts resolving matched groups at the given cascade depth.
    func beginMatches(_ groups: [MatchGroup], _ cascade: Int) {
        var cells = LinkedHashSet<Pos>()
        var pending = [PendingSpecial]()
        var scores = [ScoreEvent]()
        for g in groups {
            cells.addAll(g.cells)
            let bonus: Int
            switch g.special {
            case .STRIPED_H, .STRIPED_V: bonus = 120
            case .WRAPPED: bonus = 200
            case .COLOR_BOMB: bonus = 300
            case .NONE: bonus = 0
            }
            scores.append(ScoreEvent(points: (g.cells.count * 20 + bonus) * (cascade + 1), x: g.centerX, y: g.centerY, color: g.color))
            if g.special != .NONE, let sp = g.specialPos {
                let col: CandyColor = g.special == .COLOR_BOMB ? .NONE : g.color
                pending.append(PendingSpecial(pos: sp, color: col, special: g.special))
            }
        }
        var neighbours = LinkedHashSet<Pos>()
        for p in cells {
            for n in p.neighbours4() {
                if let c = board[n], c.playable, c.frosting > 0, !cells.contains(n) { neighbours.add(n) }
            }
        }
        resolve = Resolve(cells, cascade, [], pending, scores, neighbours, blastStart: false, comboPoints: false)
    }

    /// Starts a combo for specials swapped into [into] (the player's candy) and [from].
    @discardableResult
    func beginCombo(_ from: Pos, _ into: Pos) -> ComboStart {
        let moved = board.candyAt(into)!
        let stayed = board.candyAt(from)!
        let all = board.positions().filter { board[$0]!.playable }
        let consumed: Set<Pos> = [from, into]
        let start: ComboStart
        if moved.isBomb || stayed.isBomb {
            let bombPos = moved.isBomb ? into : from
            let otherPos = moved.isBomb ? from : into
            let other = board.candyAt(otherPos)!
            if other.isBomb {
                start = ComboStart(kind: .BOMB_BOMB, center: into, bombPos: bombPos, color: .NONE, converted: [], area: all)
                resolve = blastResolve(LinkedHashSet(all), consumed)
            } else {
                let color = other.color
                let targets = candiesOf(color)
                var converted = [Pos]()
                let kind: ComboKind
                if other.special.isStriped {
                    kind = .BOMB_STRIPED
                } else if other.special == .WRAPPED {
                    kind = .BOMB_WRAPPED
                } else {
                    kind = .BOMB_NORMAL
                }
                if kind != .BOMB_NORMAL {
                    for p in targets {
                        let c = board.candyAt(p)!
                        if p != otherPos && c.special == .NONE {
                            if kind == .BOMB_WRAPPED {
                                c.special = .WRAPPED
                            } else {
                                c.special = rng.nextBoolean() ? .STRIPED_H : .STRIPED_V
                            }
                            converted.append(p)
                        }
                    }
                }
                var area = LinkedHashSet<Pos>()
                area.add(bombPos)
                area.add(otherPos)
                area.addAll(targets)
                let cons: Set<Pos> = kind == .BOMB_NORMAL ? [bombPos] : consumed
                start = ComboStart(kind: kind, center: into, bombPos: bombPos, color: color, converted: converted, area: area.toList())
                resolve = blastResolve(area, cons)
            }
        } else {
            let s1 = moved.special
            let s2 = stayed.special
            let striped1 = s1.isStriped
            let striped2 = s2.isStriped
            var area = LinkedHashSet<Pos>()
            let kind: ComboKind
            if striped1 && striped2 {
                kind = .STRIPED_STRIPED
                area.addAll(row(into.y))
                area.addAll(column(into.x))
            } else if striped1 || striped2 {
                kind = .STRIPED_WRAPPED
                for d in -1...1 {
                    area.addAll(row(into.y + d))
                    area.addAll(column(into.x + d))
                }
            } else {
                kind = .WRAPPED_WRAPPED
                area.addAll(square(into, 2))
            }
            area.add(from)
            area.add(into)
            start = ComboStart(kind: kind, center: into, bombPos: nil, color: moved.color, converted: [], area: area.toList())
            resolve = blastResolve(area, consumed)
        }
        return start
    }

    /// Fires every special on the board at once (Sweet Frenzy). Returns false if there are none.
    @discardableResult
    func beginFireAll(_ cascade: Int = 0) -> Bool {
        let specials = board.positions().filter { board.candyAt($0)?.isSpecial == true }
        if specials.isEmpty { return false }
        resolve = Resolve(LinkedHashSet(specials), cascade, [], [], [], LinkedHashSet(), blastStart: true, comboPoints: false)
        return true
    }

    private func blastResolve(_ area: LinkedHashSet<Pos>, _ consumed: Set<Pos>) -> Resolve {
        Resolve(area, 0, consumed, [], [], LinkedHashSet(), blastStart: true, comboPoints: true)
    }

    /// Processes the current wave; returns nil when the chain reaction is over.
    func nextWave() -> Wave? {
        guard let r = resolve else { return nil }
        if r.current.isEmpty { return nil }
        var cleared = [ClearedCandy]()
        var jelly = [JellyHit]()
        var frost = [FrostingHit]()
        var triggers = [Trigger]()
        var scores = [ScoreEvent]()
        var next = LinkedHashSet<Pos>()
        if r.index == 0 {
            scores.append(contentsOf: r.groupScores)
            for p in r.neighbourFrost {
                let c = board[p]!
                if c.frosting > 0 {
                    c.frosting -= 1
                    frost.append(FrostingHit(pos: p, hpAfter: c.frosting))
                }
            }
        }
        // Bombs triggered by blasts target the colour that is most common right now.
        for p in r.current {
            if !r.processed.insert(p).inserted { continue }
            guard let cell = board[p] else { continue }
            if !cell.playable { continue }
            if cell.frosting > 0 {
                cell.frosting -= 1
                frost.append(FrostingHit(pos: p, hpAfter: cell.frosting))
                continue
            }
            if cell.jelly > 0 {
                jelly.append(JellyHit(pos: p, layersBefore: cell.jelly))
                cell.jelly -= 1
            }
            guard let candy = cell.candy else { continue }
            cell.candy = nil
            let blast = r.index > 0 || r.blastStart
            cleared.append(ClearedCandy(candy: candy.snapshot(), pos: p, byBlast: blast))
            if blast {
                let pts = (r.index == 0 && r.comboPoints) ? 60 : 30 * (r.cascade + 1)
                scores.append(ScoreEvent(points: pts, x: Float(p.x), y: Float(p.y), color: candy.color))
            }
            if candy.isSpecial && !r.consumed.contains(p) {
                let area = specialArea(candy, p, r.processed)
                triggers.append(Trigger(pos: p, special: candy.special, color: candy.color, area: area))
                for a in area where !r.processed.contains(a) { next.add(a) }
            }
        }
        let wave = Wave(index: r.index, cleared: cleared, jellyHits: jelly, frostingHits: frost, triggers: triggers, scores: scores)
        r.current = next
        r.index += 1
        return wave
    }

    /// Ends the resolve and places the specials created by the matches.
    @discardableResult
    func finishResolve() -> [CreatedSpecial] {
        guard let r = resolve else { return [] }
        resolve = nil
        var out = [CreatedSpecial]()
        for ps in r.pending {
            guard let cell = board[ps.pos] else { continue }
            if cell.open && cell.candy == nil {
                let c = Candy(newId(), ps.color, ps.special)
                cell.candy = c
                out.append(CreatedSpecial(pos: ps.pos, candy: c))
            }
        }
        return out
    }

    /// Runs every wave of the current resolve synchronously (tests and headless use).
    @discardableResult
    func resolveAll() -> [Wave] {
        var waves = [Wave]()
        while let w = nextWave() { waves.append(w) }
        return waves
    }

    private func specialArea(_ candy: Candy, _ p: Pos, _ processed: Set<Pos>) -> [Pos] {
        switch candy.special {
        case .STRIPED_H: return row(p.y)
        case .STRIPED_V: return column(p.x)
        case .WRAPPED: return square(p, 1)
        case .COLOR_BOMB:
            guard let col = mostCommonColor(processed) else { return [] }
            return candiesOf(col).filter { !processed.contains($0) }
        case .NONE: return []
        }
    }

    private func row(_ y: Int) -> [Pos] {
        if y < 0 || y >= board.height { return [] }
        return (0..<board.width).map { Pos($0, y) }.filter { board[$0]!.playable }
    }

    private func column(_ x: Int) -> [Pos] {
        if x < 0 || x >= board.width { return [] }
        return (0..<board.height).map { Pos(x, $0) }.filter { board[$0]!.playable }
    }

    private func square(_ c: Pos, _ r: Int) -> [Pos] {
        var out = [Pos]()
        for dy in -r...r {
            for dx in -r...r {
                let p = Pos(c.x + dx, c.y + dy)
                if board[p]?.playable == true { out.append(p) }
            }
        }
        return out
    }

    func candiesOf(_ color: CandyColor) -> [Pos] {
        board.positions().filter { p in
            guard let c = board.candyAt(p) else { return false }
            return !c.isBomb && c.color == color
        }
    }

    private func mostCommonColor(_ exclude: Set<Pos>) -> CandyColor? {
        var counts = [Int](repeating: 0, count: CandyColor.entries.count)
        board.forEachCell { x, y, c in
            if let k = c.candy, !k.isBomb, k.color != .NONE, !exclude.contains(Pos(x, y)) { counts[k.color.ordinal] += 1 }
        }
        var best = -1
        var bestN = 0
        for (i, n) in counts.enumerated() where n > bestN {
            bestN = n
            best = i
        }
        return best < 0 ? nil : CandyColor.entries[best]
    }

    // ------------------------------------------------------------------ gravity

    /// Kotlin's `LinkedHashMap<Int, Move>` of first positions plus the `HashMap<Int, Pos>` of final cells.
    private struct GravityState {
        var starts = [Move]()
        var startIndex = [Int: Int]()
        var posOf = [Int: Pos]()
        var spawnCount: [Int]

        init(width: Int) { spawnCount = [Int](repeating: 0, count: width) }

        func has(_ id: Int) -> Bool { startIndex[id] != nil }

        /// `starts[id] = m`: a re-put keeps the original insertion slot, like LinkedHashMap.
        mutating func put(_ m: Move) {
            if let i = startIndex[m.candy.id] {
                starts[i] = m
            } else {
                startIndex[m.candy.id] = starts.count
                starts.append(m)
            }
        }
    }

    /// Gravity and refill until stable (spec 7.7). Returns every candy that moved or spawned.
    @discardableResult
    func applyGravity() -> [Move] {
        var st = GravityState(width: board.width)
        var guardCount = 0
        while true {
            let g = guardCount
            guardCount += 1
            if !(g < 2000) { break }
            if verticalPass(&st) { continue }
            if !diagonalPass(&st) { break }
        }
        return st.starts.compactMap { s in
            guard let p = st.posOf[s.candy.id] else { return nil }
            if !s.spawned && Kt.toInt(s.fromX) == p.x && Kt.toInt(s.fromY) == p.y { return nil }
            return Move(candy: s.candy, fromX: s.fromX, fromY: s.fromY, toX: p.x, toY: p.y, spawned: s.spawned)
        }
    }

    private func verticalPass(_ st: inout GravityState) -> Bool {
        var changed = false
        for x in 0..<board.width {
            for y in 0..<board.height {
                let cell = board[x, y]!
                if !cell.open || cell.candy != nil { continue }
                var yy = y + 1
                while yy < board.height && !board[x, yy]!.playable { yy += 1 }
                if yy >= board.height {
                    let id = newId()
                    let color = randomColor()
                    let c = Candy(id, color)
                    cell.candy = c
                    let startY = board.topPlayable(x) + 1 + st.spawnCount[x]
                    st.spawnCount[x] += 1
                    st.put(Move(candy: c, fromX: Float(x), fromY: Float(startY), toX: x, toY: y, spawned: true))
                    st.posOf[c.id] = Pos(x, y)
                    changed = true
                } else {
                    let above = board[x, yy]!
                    if above.frosting > 0 { continue }
                    guard let c = above.candy else { continue }
                    above.candy = nil
                    cell.candy = c
                    if !st.has(c.id) { st.put(Move(candy: c, fromX: Float(x), fromY: Float(yy), toX: x, toY: y, spawned: false)) }
                    st.posOf[c.id] = Pos(x, y)
                    changed = true
                }
            }
        }
        return changed
    }

    private func diagonalPass(_ st: inout GravityState) -> Bool {
        for y in 0..<board.height {
            for x in 0..<board.width {
                let cell = board[x, y]!
                if !cell.open || cell.candy != nil { continue }
                let leftFirst = rng.nextBoolean()
                for k in 0..<2 {
                    let dx = (k == 0) == leftFirst ? -1 : 1
                    guard let n = board[x + dx, y + 1] else { continue }
                    if !n.open { continue }
                    guard let c = n.candy else { continue }
                    n.candy = nil
                    cell.candy = c
                    if !st.has(c.id) {
                        st.put(Move(candy: c, fromX: Float(x + dx), fromY: Float(y + 1), toX: x, toY: y, spawned: false))
                    }
                    st.posOf[c.id] = Pos(x, y)
                    return true
                }
            }
        }
        return false
    }

    // ------------------------------------------------------------------ shuffle

    /// Randomly permutes candies until there are no matches and at least one valid move.
    /// After 100 failed tries normal candies are recoloured. Returns the moves to animate.
    @discardableResult
    func shuffle() -> [Move] {
        let positions = board.positions().filter { board.candyAt($0) != nil }
        if positions.isEmpty { return [] }
        var original = [Int: Pos]()
        for p in positions { original[board.candyAt(p)!.id] = p }
        var candies = positions.map { board.candyAt($0)! }
        var ok = false
        for _ in 0..<100 {
            // Kotlin loops i = last downTo 0, so nextInt(1) is drawn too (unlike Collections.shuffle).
            var i = candies.count - 1
            while i >= 0 {
                let j = rng.nextInt(i + 1)
                let t = candies[i]
                candies[i] = candies[j]
                candies[j] = t
                i -= 1
            }
            for (k, p) in positions.enumerated() { board[p]!.candy = candies[k] }
            if !MatchFinder.hasMatch(board) && MatchFinder.findValidMove(board) != nil {
                ok = true
                break
            }
        }
        if !ok {
            for _ in 0..<200 {
                recolourNoMatches(positions)
                if MatchFinder.findValidMove(board) != nil { break }
            }
        }
        return positions.compactMap { p in
            let c = board.candyAt(p)!
            guard let o = original[c.id] else { return nil }
            return o == p ? nil : Move(candy: c, fromX: Float(o.x), fromY: Float(o.y), toX: p.x, toY: p.y, spawned: false)
        }
    }

    private func recolourNoMatches(_ positions: [Pos]) {
        // sortedWith(compareBy({ y }, { x })); positions are unique, so stability cannot matter.
        let ordered = positions.sorted { $0.y != $1.y ? $0.y < $1.y : $0.x < $1.x }
        for p in ordered {
            let c = board.candyAt(p)!
            if c.isSpecial { continue }
            c.color = BoardFill.pickColor(board, p.x, p.y, colors, rng)
        }
    }
}

/// Fills boards without pre-existing matches. Shared by the level generator and the engine.
enum BoardFill {
    /// Picks a colour that does not complete a run of 3 with the two cells to the left or below.
    static func pickColor(_ board: Board, _ x: Int, _ y: Int, _ colors: Int, _ rng: JavaRandom) -> CandyColor {
        var banned0 = -1
        var banned1 = -1
        if let l1 = MatchFinder.matchColor(board, x - 1, y), l1 == MatchFinder.matchColor(board, x - 2, y) { banned0 = l1.ordinal }
        if let d1 = MatchFinder.matchColor(board, x, y - 1), d1 == MatchFinder.matchColor(board, x, y - 2) { banned1 = d1.ordinal }
        var options = [CandyColor]()
        options.reserveCapacity(colors)
        for c in CandyColor.PLAYABLE.prefix(colors) where c.ordinal != banned0 && c.ordinal != banned1 { options.append(c) }
        return options[rng.nextInt(options.count)]
    }
}
