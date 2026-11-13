import Foundation
import GameKit

/// Deterministic level generator: every level is identical on every device (spec section 9).
/// Bit-exact with the Kotlin source: `java.util.Random(n * 7919 + 1013)` via `JavaRandom`, the same draw order
/// (including Kotlin's short-circuit `&&`/`||` skips), Float maths kept in Float and Kotlin rounding (`Kt`).
enum LevelGenerator {

    static func difficulty(_ n: Int) -> Float {
        let base = 1.0 - Foundation.exp(Double(-n) / 420.0)
        let local = Double((n - 1) % 20) / 19.0
        var d = 0.08 + base * 0.78 + (local - 0.5) * 0.12
        if n % 10 == 0 { d += 0.08 }
        if (n - 1) % 20 == 0 { d -= 0.06 }
        return Float(d.coerceIn(0.05, 1.0))
    }

    static func scorePerMove(_ colors: Int) -> Int {
        switch colors {
        case 4: return 420
        case 5: return 260
        default: return 170
        }
    }

    private static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

    private static func round500(_ v: Float) -> Int { max(500, Kt.roundToInt(v / 500) * 500) }

    static func generate(_ n: Int) -> Level {
        let rnd = JavaRandom(Int64(n) * 7919 + 1013)
        return n <= 6 ? tutorial(n, rnd) : procedural(n, rnd)
    }

    // ------------------------------------------------------------------ tutorials 1–6

    private static func tutorial(_ n: Int, _ rnd: JavaRandom) -> Level {
        let d = difficulty(n)
        switch n {
        case 1:
            return build(n, 7, 7, 4, 15, .SCORE, 2000, [], [2000, 3500, 5500], full(7, 7), nil, nil, d, rnd)
        case 2:
            return build(n, 8, 8, 4, 15, .SCORE, 3500, [], [3500, 5500, 8000], full(8, 8), nil, nil, d, rnd)
        case 3:
            var mask = full(8, 8)
            for (x, y) in [(0, 0), (7, 0), (0, 7), (7, 7)] { mask[x + y * 8] = false }
            return build(n, 8, 8, 5, 20, .COLLECT, 0, [CollectTarget(.RED, 20)], nonScoreStars(20, 5), mask, nil, nil, d, rnd)
        case 4:
            var jelly = [Int](repeating: 0, count: 64)
            for y in 0..<8 {
                for x in 0..<8 where abs(Float(x) - 3.5) + abs(Float(y) - 3.5) <= 2.5 { jelly[x + y * 8] = 1 }
            }
            return build(n, 8, 8, 5, 20, .JELLY, 0, [], nonScoreStars(20, 5), full(8, 8), jelly, nil, d, rnd)
        case 5:
            var frost = [Int](repeating: 0, count: 64)
            for (x, y) in [(1, 3), (6, 3), (2, 2), (5, 2), (3, 1), (4, 1)] { frost[x + y * 8] = 1 }
            return build(n, 8, 8, 5, 22, .SCORE, 4000, [], [4000, 6500, 9000], full(8, 8), nil, frost, d, rnd)
        default:
            var jelly = [Int](repeating: 0, count: 81)
            for y in 0..<3 {
                for x in 0..<9 { jelly[x + y * 9] = 1 }
            }
            return build(n, 9, 9, 5, 22, .JELLY, 0, [], nonScoreStars(22, 5), full(9, 9), jelly, nil, d, rnd)
        }
    }

    private static func nonScoreStars(_ moves: Int, _ colors: Int) -> [Int] {
        let spm = scorePerMove(colors)
        return [0, round500(Float(moves * spm) * 0.6), round500(Float(moves * spm) * 0.95)]
    }

    private static func full(_ w: Int, _ h: Int) -> [Bool] { [Bool](repeating: true, count: w * h) }

    // ------------------------------------------------------------------ procedural 7–2000

    private static func procedural(_ n: Int, _ rnd: JavaRandom) -> Level {
        let d = difficulty(n)
        let w: Int
        let h: Int
        if n < 25 {
            w = 8
            h = 8
        } else {
            w = rnd.nextFloat() < 0.7 ? 9 : 8
            h = rnd.nextFloat() < 0.75 ? 9 : 8
        }
        let kinds: Int
        if n < 15 {
            kinds = 2
        } else if n < 40 {
            kinds = 5
        } else {
            kinds = 8
        }
        let minCells = max(36, Kt.toInt((Double(w * h) * 0.55).rounded(.up)))
        var mask = full(w, h)
        for _ in 0..<8 {
            let m = shapeMask(rnd.nextInt(kinds), w, h)
            if m.reduce(0, { $0 + ($1 ? 1 : 0) }) >= minCells {
                mask = m
                break
            }
        }

        let colors = n <= 40 ? 5 : (rnd.nextFloat() < lerp(0.30, 0.85, d) ? 6 : 5)
        let r = rnd.nextFloat()
        let goal: GoalType
        if n < 15 {
            if r < 0.35 {
                goal = .SCORE
            } else if r < 0.70 {
                goal = .COLLECT
            } else {
                goal = .JELLY
            }
        } else {
            if r < 0.20 {
                goal = .SCORE
            } else if r < 0.52 {
                goal = .JELLY
            } else if r < 0.82 {
                goal = .COLLECT
            } else {
                goal = .FROSTING
            }
        }

        var frosting = [Int](repeating: 0, count: w * h)
        if goal == .FROSTING || (n >= 10 && rnd.nextFloat() < lerp(0.25, 0.75, d)) {
            let count = goal == .FROSTING ? Kt.roundToInt(lerp(6, 18, d)) : Kt.roundToInt(lerp(3, 12, d))
            placeFrosting(&frosting, mask, w, h, count, d, rnd)
        }

        var jelly = [Int](repeating: 0, count: w * h)
        if goal == .JELLY { placeJelly(&jelly, mask, frosting, w, h, d, rnd) }

        let spm = scorePerMove(colors)
        let moves: Int
        var target = 0
        var collect = [CollectTarget]()
        let stars: [Int]
        switch goal {
        case .SCORE:
            moves = Kt.roundToInt(lerp(30, 20, d) + Float(rnd.nextInt(7) - 3))
            target = max(1000, Kt.roundToInt(Float(moves * spm) * lerp(0.72, 1.08, d) / 500) * 500)
            stars = [target, round500(Float(target) * 1.5), round500(Float(target) * 2.1)]
        case .JELLY:
            let layers = jelly.reduce(0, +)
            let k: Float = colors == 6 ? 1.1 : 0.95
            moves = Kt.toInt((8 + Float(layers) * lerp(0.60, 0.42, d) * k).rounded(.up)).coerceIn(15, 50)
            stars = nonScoreStars(moves, colors)
        case .COLLECT:
            let colourCount = (d > 0.4 && rnd.nextFloat() < 0.5) ? 2 : 1
            moves = Kt.roundToInt(lerp(26, 20, d) + Float(rnd.nextInt(5) - 2))
            let raw = Float(moves) * lerp(1.0, 1.45, d) * Kt.sqrt(6 / Float(colors)) / Float(colourCount) * 1.1 / 5
            let per = max(10, Kt.roundToInt(raw) * 5)
            var pool = Array(CandyColor.PLAYABLE.prefix(colors))
            for _ in 0..<colourCount { collect.append(CollectTarget(pool.remove(at: rnd.nextInt(pool.count)), per)) }
            stars = nonScoreStars(moves, colors)
        case .FROSTING:
            let totalHp = frosting.reduce(0, +)
            moves = Kt.roundToInt(10 + Float(totalHp) * lerp(0.95, 0.65, d)).coerceIn(15, 45)
            stars = nonScoreStars(moves, colors)
        }
        return build(n, w, h, colors, moves, goal, target, collect, stars, mask, jelly, frosting, d, rnd)
    }

    /// Symmetric board shapes (spec 9).
    static func shapeMask(_ kind: Int, _ w: Int, _ h: Int) -> [Bool] {
        var m = [Bool](repeating: true, count: w * h)
        let cx = Float(w - 1) / 2
        let cy = Float(h - 1) / 2
        for y in 0..<h {
            for x in 0..<w {
                let dx = abs(Float(x) - cx)
                let dy = abs(Float(y) - cy)
                let keep: Bool
                switch kind {
                case 1:
                    keep = dx + dy <= cx + cy - 1.5
                case 2:
                    keep = !((y == 0 || y == h - 1) && dx < 1)
                case 3:
                    let cw = w / 4
                    let ch = h / 4
                    let corner = (x < cw || x >= w - cw) && (y < ch || y >= h - ch)
                    keep = !corner
                case 4:
                    keep = dx + dy <= (cx + cy) / 2 + 1
                case 5:
                    let hw: Float = w % 2 == 0 ? 1 : 1.5
                    let hh: Float = h % 2 == 0 ? 1 : 1.5
                    keep = !(dx < hw && dy < hh)
                case 6:
                    keep = dx <= cx - 2 + dy * 0.8 + 0.01
                case 7:
                    let crenel = y == h - 1 && min(x, w - 1 - x) % 2 == 1
                    let notch = (x == 0 || x == w - 1) && dy < 1
                    keep = !(crenel || notch)
                default:
                    keep = true
                }
                m[x + y * w] = keep
            }
        }
        return m
    }

    private static func topPlayable(_ mask: [Bool], _ w: Int, _ h: Int, _ x: Int) -> Int {
        var y = h - 1
        while y >= 0 {
            if mask[x + y * w] { return y }
            y -= 1
        }
        return -1
    }

    private static func placeFrosting(_ frost: inout [Int], _ mask: [Bool], _ w: Int, _ h: Int, _ count: Int, _ d: Float, _ rnd: JavaRandom) {
        let rowPlayable = (0..<h).map { y in (0..<w).reduce(0) { $0 + (mask[$1 + y * w] ? 1 : 0) } }
        var rowCount = [Int](repeating: 0, count: h)
        let half = (w - 1) / 2
        var placed = 0
        var tries = 0
        while placed < count && tries < 400 {
            tries += 1
            let x = rnd.nextInt(half + 1)
            let y = rnd.nextInt(h - 1)
            let xm = w - 1 - x
            let i = x + y * w
            let im = xm + y * w
            if !mask[i] || !mask[im] { continue }
            if frost[i] > 0 { continue }
            if y == topPlayable(mask, w, h, x) || y == topPlayable(mask, w, h, xm) { continue }
            let add = x == xm ? 1 : 2
            if rowCount[y] + add > rowPlayable[y] / 2 { continue }
            let hp = (d > 0.45 && rnd.nextFloat() < 0.7 * d) ? 2 : 1
            frost[i] = hp
            frost[im] = hp
            if (0..<h).contains(where: { !allFeedable(frost, mask, w, h, $0) }) {
                frost[i] = 0
                frost[im] = 0
                continue
            }
            rowCount[y] += add
            placed += add
        }
    }

    /// Every open cell directly under frosting in row [y] must still be reachable diagonally
    /// (gravity only slides from the upper-left/right), otherwise it would stay empty after a clear.
    private static func allFeedable(_ frost: [Int], _ mask: [Bool], _ w: Int, _ h: Int, _ y: Int) -> Bool {
        func open(_ x: Int, _ yy: Int) -> Bool {
            x >= 0 && x < w && yy >= 0 && yy < h && mask[x + yy * w] && frost[x + yy * w] == 0
        }
        for x in 0..<w {
            if frost[x + y * w] == 0 { continue }
            var yb = y - 1
            while yb >= 0 && !mask[x + yb * w] { yb -= 1 }
            if yb < 0 || frost[x + yb * w] > 0 { continue }
            if !open(x - 1, yb + 1) && !open(x + 1, yb + 1) { return false }
        }
        return true
    }

    /// True when every open cell below frosting can be refilled (used by tests).
    static func isRefillable(_ level: Level) -> Bool {
        (0..<level.height).allSatisfy { allFeedable(level.frosting, level.playable, level.width, level.height, $0) }
    }

    private static func placeJelly(_ jelly: inout [Int], _ mask: [Bool], _ frost: [Int], _ w: Int, _ h: Int, _ d: Float, _ rnd: JavaRandom) {
        let cx = Float(w - 1) / 2
        let cy = Float(h - 1) / 2
        let pattern = rnd.nextInt(5)
        let bottomRows = rnd.nextBoolean() ? 3 : 4
        func open(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < w && y >= 0 && y < h && mask[x + y * w] }
        for y in 0..<h {
            for x in 0..<w {
                let i = x + y * w
                if !mask[i] || frost[i] > 0 { continue }
                let on: Bool
                switch pattern {
                case 0: on = abs(Float(x) - cx) + abs(Float(y) - cy) <= (cx + cy) / 2
                case 1: on = y < bottomRows
                case 2: on = !open(x - 1, y) || !open(x + 1, y) || !open(x, y - 1) || !open(x, y + 1)
                case 3: on = (x + y) % 2 == 0
                default: on = true
                }
                if on { jelly[i] = 1 }
            }
        }
        if d > 0.4 {
            for y in 0..<h {
                for x in 0..<w {
                    let i = x + y * w
                    if jelly[i] > 0 && abs(Float(y) - cy) <= 1.5 && rnd.nextFloat() < d { jelly[i] = 2 }
                }
            }
        }
        var guardCount = 0
        while jelly.reduce(0, +) < 8 {
            let g = guardCount
            guardCount += 1
            if !(g < 500) { break }
            let i = rnd.nextInt(w * h)
            if mask[i] && frost[i] == 0 && jelly[i] < 2 { jelly[i] += 1 }
        }
    }

    // ------------------------------------------------------------------ assembly

    private static func build(
        _ n: Int, _ w: Int, _ h: Int, _ colors: Int, _ moves: Int, _ goal: GoalType, _ target: Int,
        _ collect: [CollectTarget], _ stars: [Int], _ mask: [Bool],
        _ jelly: [Int]?, _ frost: [Int]?, _ d: Float, _ rnd: JavaRandom
    ) -> Level {
        var j = jelly ?? [Int](repeating: 0, count: w * h)
        var f = frost ?? [Int](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            if !mask[i] {
                j[i] = 0
                f[i] = 0
            }
            if f[i] > 0 { j[i] = 0 }
        }
        let initial = initialFill(w, h, colors, mask, f, rnd)
        return Level(
            number: n, width: w, height: h, colors: colors, moves: moves, goal: goal, scoreTarget: target,
            collect: collect, starScores: stars, playable: mask, jelly: j, frosting: f, initial: initial, difficulty: d
        )
    }

    /// Seeded fill with no pre-existing matches and at least one valid move (up to 50 tries).
    private static func initialFill(_ w: Int, _ h: Int, _ colors: Int, _ mask: [Bool], _ frost: [Int], _ rnd: JavaRandom) -> [Int] {
        var result = [Int](repeating: -1, count: w * h)
        for _ in 0..<50 {
            let cells = (0..<(w * h)).map { Cell(mask[$0], jelly: 0, frosting: frost[$0]) }
            let board = Board(w, h, cells)
            var id = 1
            for y in 0..<h {
                for x in 0..<w {
                    let c = cells[x + y * w]
                    if c.open {
                        c.candy = Candy(id, BoardFill.pickColor(board, x, y, colors, rnd))
                        id += 1
                    }
                }
            }
            result = cells.map { $0.candy?.color.ordinal ?? -1 }
            if MatchFinder.findValidMove(board) != nil { break }
        }
        return result
    }
}
