import SwiftUI
import UIKit
import GameKit

/**
 * "Colour-blind symbols" (Settings › Gameplay): a small white symbol with a dark outline on every candy —
 * red ●, orange ▲, yellow ★, green ■, blue ◆, purple ✚ (colour bombs have none).
 * Shapes live in a unit box (−1…1); the board draws pre-rendered device-scale sprites ([ColorBlindSymbolTable]),
 * static canvases (goal icons, the onboarding demo) draw the paths.
 */
enum ColorBlindSymbols {
    /// Symbol size as a fraction of the cell.
    static let SIZE: CGFloat = 0.4
    /// Outline width in unit-box units (drawn as a stroke under the white fill).
    static let OUTLINE: CGFloat = 0.36
    static let outline = RGBA(argb: 0xFF2A1240).with(alpha: 0.9)

    private static let shapes: [Path?] = CandyColor.entries.map { shape($0) }

    static func path(_ color: CandyColor) -> Path? { shapes[color.ordinal] }

    private static func shape(_ color: CandyColor) -> Path? {
        switch color {
        case .RED:
            return Path(ellipseIn: CGRect(x: -0.66, y: -0.66, width: 1.32, height: 1.32))
        case .ORANGE:
            var p = Path()
            p.move(to: CGPoint(x: 0, y: -0.8))
            p.addLine(to: CGPoint(x: 0.82, y: 0.62))
            p.addLine(to: CGPoint(x: -0.82, y: 0.62))
            p.closeSubpath()
            return p
        case .YELLOW:
            return starPath(0, 0.06, 0.9, inner: 0.45)
        case .GREEN:
            return Path(roundedRect: CGRect(x: -0.6, y: -0.6, width: 1.2, height: 1.2), cornerRadius: 0.12, style: .circular)
        case .BLUE:
            var p = Path()
            p.move(to: CGPoint(x: 0, y: -0.9))
            p.addLine(to: CGPoint(x: 0.68, y: 0))
            p.addLine(to: CGPoint(x: 0, y: 0.9))
            p.addLine(to: CGPoint(x: -0.68, y: 0))
            p.closeSubpath()
            return p
        case .PURPLE:
            let a: CGFloat = 0.25
            let l: CGFloat = 0.82
            var p = Path()
            p.move(to: CGPoint(x: -a, y: -l))
            p.addLine(to: CGPoint(x: a, y: -l))
            p.addLine(to: CGPoint(x: a, y: -a))
            p.addLine(to: CGPoint(x: l, y: -a))
            p.addLine(to: CGPoint(x: l, y: a))
            p.addLine(to: CGPoint(x: a, y: a))
            p.addLine(to: CGPoint(x: a, y: l))
            p.addLine(to: CGPoint(x: -a, y: l))
            p.addLine(to: CGPoint(x: -a, y: a))
            p.addLine(to: CGPoint(x: -l, y: a))
            p.addLine(to: CGPoint(x: -l, y: -a))
            p.addLine(to: CGPoint(x: -a, y: -a))
            p.closeSubpath()
            return p
        case .NONE:
            return nil
        }
    }

    /// Sprite of one symbol, [px] pixels square (outline included).
    static func render(_ color: CandyColor, _ px: Int) -> CGImage? {
        guard let shape = path(color), px > 0 else { return nil }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: px, height: px), format: fmt).image { r in
            let c = r.cgContext
            let half = CGFloat(px) / 2
            // The unit box plus half the outline fits the sprite.
            let k = half / (1 + OUTLINE / 2)
            c.translateBy(x: half, y: half)
            c.scaleBy(x: k, y: k)
            c.addPath(shape.cgPath)
            c.setLineJoin(.round)
            c.setLineWidth(OUTLINE)
            c.setStrokeColor(UIColor(red: CGFloat(outline.r), green: CGFloat(outline.g), blue: CGFloat(outline.b), alpha: CGFloat(outline.a)).cgColor)
            c.strokePath()
            c.addPath(shape.cgPath)
            c.setFillColor(UIColor.white.cgColor)
            c.fillPath()
        }
        return img.cgImage
    }
}

extension GraphicsContext {
    /// Path-drawn symbol for a candy drawn at ([cx], [cy]) in a [cell]; [scale] / [alpha] follow the candy.
    func drawColorBlindSymbol(_ color: CandyColor, _ cx: CGFloat, _ cy: CGFloat, _ cell: CGFloat, scale: CGFloat = 1, alpha: CGFloat = 1) {
        guard let shape = ColorBlindSymbols.path(color), cell > 0, scale > 0, alpha > 0 else { return }
        var g = self
        g.opacity *= Double(min(1, alpha))
        g.translateBy(x: cx, y: cy)
        let k = cell * ColorBlindSymbols.SIZE * scale / (2 + ColorBlindSymbols.OUTLINE)
        g.scaleBy(x: k, y: k)
        g.stroke(shape, with: ColorBlindSymbols.outline.shading, style: StrokeStyle(lineWidth: ColorBlindSymbols.OUTLINE, lineJoin: .round))
        g.fill(shape, with: .color(.white))
    }
}

/**
 * The board's symbol sprites for one cell size: rendered once at device scale, resolved once per frame,
 * drawn like the candy bitmaps (destination snapped to device pixels).
 */
@MainActor
final class ColorBlindSymbolTable {
    private var px = -1
    private var images = [Image?](repeating: nil, count: CandyColor.entries.count)
    private var resolved = [GraphicsContext.ResolvedImage?](repeating: nil, count: CandyColor.entries.count)
    private var resolvedFrame = [Int](repeating: -1, count: CandyColor.entries.count)
    private var frame = 0
    private var size: CGFloat = 0
    private var scale: CGFloat = 1

    func beginFrame(cell: CGFloat, scale: CGFloat) {
        let s = cell * ColorBlindSymbols.SIZE
        let p = Int((s * scale).rounded(.up))
        if p != px {
            px = p
            for i in images.indices {
                images[i] = nil
                resolved[i] = nil
                resolvedFrame[i] = -1
            }
        }
        frame &+= 1
        size = s
        self.scale = scale
    }

    private func image(_ ctx: GraphicsContext, _ color: CandyColor) -> GraphicsContext.ResolvedImage? {
        let k = color.ordinal
        if resolvedFrame[k] == frame, let r = resolved[k] { return r }
        if images[k] == nil, let cg = ColorBlindSymbols.render(color, px) { images[k] = Image(decorative: cg, scale: 1) }
        guard let img = images[k] else { return nil }
        let r = ctx.resolve(img)
        resolved[k] = r
        resolvedFrame[k] = frame
        return r
    }

    func draw(_ ctx: GraphicsContext, _ color: CandyColor, _ cx: CGFloat, _ cy: CGFloat, _ scaleX: CGFloat, _ scaleY: CGFloat, _ alpha: CGFloat) {
        if color == .NONE || alpha <= 0 || scaleX <= 0 || scaleY <= 0 || px <= 0 { return }
        guard let img = image(ctx, color) else { return }
        let w = size * scaleX
        let h = size * scaleY
        let x0 = ((cx - w / 2) * scale).rounded() / scale
        let y0 = ((cy - h / 2) * scale).rounded() / scale
        let rect = CGRect(x: x0, y: y0, width: max(1, (w * scale).rounded()) / scale, height: max(1, (h * scale).rounded()) / scale)
        if alpha < 1 {
            var c = ctx
            c.opacity *= Double(alpha)
            c.draw(img, in: rect)
        } else {
            ctx.draw(img, in: rect)
        }
    }
}
