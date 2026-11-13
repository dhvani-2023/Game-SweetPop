import Foundation

/// Booster helpers built only on the public engine API (no change to the ported rules, RNG use or level generation).
extension BoardEngine {
    /// Lollipop Hammer: resolves the candy at [p] as a one-cell match through `beginMatches` — it is cleared (the
    /// jelly under it is hit, neighbouring frosting cracks as next to any match) and a special there fires.
    /// Then run `nextWave()` / `finishResolve()` / `applyGravity()` as for a match. Draws nothing from the RNG.
    @discardableResult
    func beginHammer(_ p: Pos) -> Bool {
        guard let candy = board.candyAt(p), board[p]?.open == true else { return false }
        var cells = LinkedHashSet<Pos>()
        cells.add(p)
        beginMatches([MatchGroup(cells, candy.color, [], .NONE, nil)], 0)
        return true
    }
}
