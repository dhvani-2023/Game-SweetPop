import Foundation
@testable import SweetPop

/// Builds boards from text, top row first. R O Y G B P = candies, '.' = empty open cell,
/// '#' = hole, 'F' = frosting (1 hp), '*' = colour bomb. Specials are set afterwards through `Board[x, y]`.
enum TestBoards {
    private static var id = 1

    static func parse(_ rows: String...) -> Board { parse(rows) }

    static func parse(_ rows: [String]) -> Board {
        let h = rows.count
        let w = rows[0].count
        var cells = (0..<(w * h)).map { _ in Cell(true) }
        for r in 0..<h {
            let y = h - 1 - r
            let row = Array(rows[r])
            for x in 0..<w {
                let ch = row[x]
                let cell: Cell
                switch ch {
                case "#": cell = Cell(false)
                case "F": cell = Cell(true, frosting: 1)
                case ".": cell = Cell(true)
                case "*": cell = Cell(true, candy: Candy(nextId(), .NONE, .COLOR_BOMB))
                default: cell = Cell(true, candy: Candy(nextId(), color(ch)))
                }
                cells[x + y * w] = cell
            }
        }
        return Board(w, h, cells)
    }

    /// Kotlin `id++`.
    private static func nextId() -> Int {
        let v = id
        id += 1
        return v
    }

    static func color(_ ch: Character) -> CandyColor {
        switch ch {
        case "R": return .RED
        case "O": return .ORANGE
        case "Y": return .YELLOW
        case "G": return .GREEN
        case "B": return .BLUE
        case "P": return .PURPLE
        default: fatalError("Unknown candy '\(ch)'")
        }
    }
}
