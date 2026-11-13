import Foundation
import GameKit

enum Ease: String, CaseIterable {
    case LINEAR, IN, IN_OUT, OUT_BOUNCE, OUT_BACK
}

extension Ease {
    func apply(_ t: Float) -> Float {
        let c = t.coerceIn(0, 1)
        switch self {
        case .LINEAR: return c
        case .IN: return BoardEasing.inQuad(c)
        case .IN_OUT: return BoardEasing.inOut(c)
        case .OUT_BOUNCE: return BoardEasing.outBounce(c)
        case .OUT_BACK: return BoardEasing.outBack(c)
        }
    }
}

/// The curves of Kotlin `design.Easing` that [Ease] uses, copied here so the game model does not depend on
/// the design layer (same Float maths and operation order as the Kotlin source).
enum BoardEasing {
    static func inOut(_ t: Float) -> Float {
        t < 0.5 ? 2 * t * t : 1 - Kt.pow(-2 * t + 2, 2) / 2
    }

    static func inQuad(_ t: Float) -> Float { t * t }

    static func outBack(_ t: Float, _ s: Float = 1.70158) -> Float {
        let u = t - 1
        return 1 + (s + 1) * u * u * u + s * u * u
    }

    static func outBounce(_ t: Float) -> Float {
        let n1: Float = 7.5625
        let d1: Float = 2.75
        var x = t
        if x < 1 / d1 {
            return n1 * x * x
        } else if x < 2 / d1 {
            x -= 1.5 / d1
            return n1 * x * x + 0.75
        } else if x < 2.5 / d1 {
            x -= 2.25 / d1
            return n1 * x * x + 0.9375
        } else {
            x -= 2.625 / d1
            return n1 * x * x + 0.984375
        }
    }
}

/// A candy sliding from one (cell-coordinate) position to its cell.
///
/// Named `Motion` like Kotlin. This shadows GameKit's `Motion` (Reduce Motion) inside the app module, so the
/// two GameKit members are forwarded below and `Motion.reduce` keeps working for UI code.
final class Motion {
    let fromX: Float
    let fromY: Float
    let toX: Float
    let toY: Float
    let start: Float
    let dur: Float
    let ease: Ease
    let squash: Bool

    init(_ fromX: Float, _ fromY: Float, _ toX: Float, _ toY: Float, _ start: Float, _ dur: Float, _ ease: Ease, squash: Bool = false) {
        self.fromX = fromX
        self.fromY = fromY
        self.toX = toX
        self.toY = toY
        self.start = start
        self.dur = dur
        self.ease = ease
        self.squash = squash
    }

    var end: Float { start + dur }
}

#if canImport(UIKit)
extension Motion {
    /// Forwards `GameKit.Motion.reduce` (iOS Reduce Motion or the app's own toggle).
    @MainActor static var reduce: Bool { GameKit.Motion.reduce }

    /// Forwards `GameKit.Motion.appReduceMotion`.
    @MainActor static var appReduceMotion: Bool {
        get { GameKit.Motion.appReduceMotion }
        set { GameKit.Motion.appReduceMotion = newValue }
    }
}
#endif

final class PopAnim {
    let color: CandyColor
    let special: SpecialType
    let x: Int
    let y: Int
    let start: Float

    init(_ color: CandyColor, _ special: SpecialType, _ x: Int, _ y: Int, _ start: Float) {
        self.color = color
        self.special = special
        self.x = x
        self.y = y
        self.start = start
    }
}

final class JellyPopAnim {
    let x: Int
    let y: Int
    let layers: Int
    let start: Float

    init(_ x: Int, _ y: Int, _ layers: Int, _ start: Float) {
        self.x = x
        self.y = y
        self.layers = layers
        self.start = start
    }
}

/// Purely visual state of the board, keyed by candy id or cell index and timed on the game clock.
/// The model (Board) always holds the final state; these describe how to get there on screen.
final class BoardVisuals {
    var motions = [Int: Motion]()
    var pops = [PopAnim]()
    var jellyPops = [JellyPopAnim]()
    var frostHits = [Int: Float]()
    var grow = [Int: Float]()
    var pulses = [Int: Float]()
    var selected: Pos?
    var selectedAt: Float = 0
    var hint: PosPair?
    var hintAt: Float = 0

    init() {}

    func clear() {
        motions.removeAll()
        pops.removeAll()
        jellyPops.removeAll()
        frostHits.removeAll()
        grow.removeAll()
        pulses.removeAll()
        selected = nil
        hint = nil
    }

    func prune(_ now: Float) {
        Self.removeAll(&motions) { now > $0.end + 0.3 }
        pops.removeAll { now - $0.start > 0.32 }
        jellyPops.removeAll { now - $0.start > 0.4 }
        Self.removeAll(&frostHits) { now - $0 > 0.4 }
        Self.removeAll(&grow) { now - $0 > 0.45 }
        Self.removeAll(&pulses) { now - $0 > 0.6 }
    }

    /// `map.entries.removeAll { … }` without allocating on frames where nothing expires.
    private static func removeAll<V>(_ map: inout [Int: V], where dead: (V) -> Bool) {
        guard map.values.contains(where: dead) else { return }
        map = map.filter { !dead($0.value) }
    }
}
