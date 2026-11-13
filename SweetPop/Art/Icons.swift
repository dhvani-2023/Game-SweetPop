import SwiftUI
import GameKit

/// A vector icon on a 24×24 viewport (Compose `ImageVector`): one or more filled paths.
struct ImageVector {
    struct VectorPath {
        let path: Path
        let evenOdd: Bool
    }

    let name: String
    let viewport: CGFloat
    let paths: [VectorPath]
}

/// White vector icons on a 24×24 viewport; tint them where used.
enum Icons {
    private static func icon(_ name: String, _ paths: String...) -> ImageVector {
        ImageVector(name: name, viewport: 24, paths: paths.map { .init(path: PathData.parse($0), evenOdd: true) })
    }

    private static func built(_ name: String, _ block: (inout Path) -> Void) -> ImageVector {
        var p = Path()
        block(&p)
        return ImageVector(name: name, viewport: 24, paths: [.init(path: p, evenOdd: false)])
    }

    static let Settings: ImageVector = built("settings") { p in
        // Gear: 8 teeth around a ring with a hole.
        let teeth = 8
        let rOut: Float = 10.2
        let rIn: Float = 7.6
        for i in 0..<(teeth * 2) {
            let a0 = Float(Double(i) * Double.pi / Double(teeth))
            let r = i % 2 == 0 ? rOut : rIn
            let half = Float(Double.pi / Double(teeth) * 0.5)
            let p0 = a0 - half
            let p1 = a0 + half
            let x0 = 12 + r * Kt.cos(p0)
            let y0 = 12 + r * Kt.sin(p0)
            if i == 0 { p.move(to: CGPoint(x: CGFloat(x0), y: CGFloat(y0))) } else { p.addLine(to: CGPoint(x: CGFloat(x0), y: CGFloat(y0))) }
            p.addLine(to: CGPoint(x: CGFloat(12 + r * Kt.cos(p1)), y: CGFloat(12 + r * Kt.sin(p1))))
        }
        p.closeSubpath()
        // Hole drawn in the opposite direction so non-zero filling cuts it out.
        let hr: Float = 3.4
        p.move(to: CGPoint(x: CGFloat(12 + hr), y: 12))
        for k in 1...24 {
            let a = Float(Double(-k) * 2 * Double.pi / 24)
            p.addLine(to: CGPoint(x: CGFloat(12 + hr * Kt.cos(a)), y: CGFloat(12 + hr * Kt.sin(a))))
        }
        p.closeSubpath()
    }

    static let Pause = icon("pause", "M6,5h4v14H6zM14,5h4v14h-4z")
    static let Play = icon("play", "M8,5v14l11,-7z")
    static let Close = icon("close", "M19,6.41L17.59,5 12,10.59 6.41,5 5,6.41 10.59,12 5,17.59 6.41,19 12,13.41 17.59,19 19,17.59 13.41,12z")
    static let Back = icon("back", "M20,11H7.83l5.59,-5.59L12,4l-8,8 8,8 1.41,-1.41L7.83,13H20v-2z")
    static let Heart = icon(
        "heart",
        "M12,21.35l-1.45,-1.32C5.4,15.36 2,12.28 2,8.5 2,5.42 4.42,3 7.5,3c1.74,0 3.41,0.81 4.5,2.09C13.09,3.81 14.76,3 16.5,3 19.58,3 22,5.42 22,8.5c0,3.78 -3.4,6.86 -8.55,11.54L12,21.35z"
    )
    static let Star = icon("star", "M12,17.27L18.18,21l-1.64,-7.03L22,9.24l-7.19,-0.61L12,2 9.19,8.63 2,9.24l5.46,4.73L5.82,21z")
    static let Lock = icon(
        "lock",
        "M18,8h-1V6c0,-2.76 -2.24,-5 -5,-5S7,3.24 7,6v2H6c-1.1,0 -2,0.9 -2,2v10c0,1.1 0.9,2 2,2h12c1.1,0 2,-0.9 2,-2V10c0,-1.1 -0.9,-2 -2,-2zM12,17c-1.1,0 -2,-0.9 -2,-2s0.9,-2 2,-2 2,0.9 2,2 -0.9,2 -2,2zM15.1,8H8.9V6c0,-1.71 1.39,-3.1 3.1,-3.1 1.71,0 3.1,1.39 3.1,3.1v2z"
    )
    static let Music = icon("music", "M12,3v10.55c-0.59,-0.34 -1.27,-0.55 -2,-0.55 -2.21,0 -4,1.79 -4,4s1.79,4 4,4 4,-1.79 4,-4V7h4V3h-6z")
    static let Sound = icon(
        "sound",
        "M3,9v6h4l5,5V4L7,9H3z",
        "M16.5,12c0,-1.77 -1.02,-3.29 -2.5,-4.03v8.05c1.48,-0.73 2.5,-2.25 2.5,-4.02z",
        "M14,3.23v2.06c2.89,0.86 5,3.54 5,6.71s-2.11,5.85 -5,6.71v2.06c4.01,-0.91 7,-4.49 7,-8.77s-2.99,-7.86 -7,-8.77z"
    )
    static let Vibration = icon(
        "vibration",
        "M0,15h2V9H0v6zM3,17h2V7H3v10zM22,9v6h2V9h-2zM19,17h2V7h-2v10z",
        "M16.5,3h-9C6.67,3 6,3.67 6,4.5v15c0,0.83 0.67,1.5 1.5,1.5h9c0.83,0 1.5,-0.67 1.5,-1.5v-15c0,-0.83 -0.67,-1.5 -1.5,-1.5zM16,19H8V5h8v14z"
    )
    static let Sun: ImageVector = built("sun") { p in
        let r: Float = 4.6
        p.move(to: CGPoint(x: CGFloat(12 + r), y: 12))
        for k in 1...24 {
            let a = Float(Double(k) * 2 * Double.pi / 24)
            p.addLine(to: CGPoint(x: CGFloat(12 + r * Kt.cos(a)), y: CGFloat(12 + r * Kt.sin(a))))
        }
        p.closeSubpath()
        for i in 0..<8 {
            let a = Float(Double(i) * Double.pi / 4)
            let w: Float = 0.22
            p.move(to: CGPoint(x: CGFloat(12 + 6.6 * Kt.cos(a - w)), y: CGFloat(12 + 6.6 * Kt.sin(a - w))))
            p.addLine(to: CGPoint(x: CGFloat(12 + 10.4 * Kt.cos(a)), y: CGFloat(12 + 10.4 * Kt.sin(a))))
            p.addLine(to: CGPoint(x: CGFloat(12 + 6.6 * Kt.cos(a + w)), y: CGFloat(12 + 6.6 * Kt.sin(a + w))))
            p.closeSubpath()
        }
    }
    static let Moon = icon(
        "moon",
        "M12,3c-4.97,0 -9,4.03 -9,9s4.03,9 9,9 9,-4.03 9,-9c0,-0.46 -0.04,-0.92 -0.1,-1.36 -0.98,1.37 -2.58,2.26 -4.4,2.26 -2.98,0 -5.4,-2.42 -5.4,-5.4 0,-1.81 0.89,-3.42 2.26,-4.4C12.92,3.04 12.46,3 12,3z"
    )
    static let Auto = icon("auto", "M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM12,20V4c4.42,0 8,3.58 8,8s-3.58,8 -8,8z")
    static let Bulb = icon(
        "bulb",
        "M9,21c0,0.55 0.45,1 1,1h4c0.55,0 1,-0.45 1,-1v-1H9v1z",
        "M12,2C8.14,2 5,5.14 5,9c0,2.38 1.19,4.47 3,5.74V17c0,0.55 0.45,1 1,1h6c0.55,0 1,-0.45 1,-1v-2.26c1.81,-1.27 3,-3.36 3,-5.74 0,-3.86 -3.14,-7 -7,-7z"
    )
    static let Replay = icon("replay", "M12,5V1L7,6l5,5V7c3.31,0 6,2.69 6,6s-2.69,6 -6,6 -6,-2.69 -6,-6H4c0,4.42 3.58,8 8,8s8,-3.58 8,-8 -3.58,-8 -8,-8z")
    static let Document = icon(
        "document",
        "M14,2H6c-1.1,0 -1.99,0.9 -1.99,2L4,20c0,1.1 0.89,2 1.99,2H18c1.1,0 2,-0.9 2,-2V8l-6,-6zM16,18H8v-2h8v2zM16,14H8v-2h8v2zM13,9V3.5L18.5,9H13z"
    )
    static let Shield = icon(
        "shield",
        "M12,1L3,5v6c0,5.55 3.84,10.74 9,12 5.16,-1.26 9,-6.45 9,-12V5l-9,-4zM10,17l-4,-4 1.41,-1.41L10,14.17l6.59,-6.59L18,9l-8,8z"
    )
    static let Refresh = icon(
        "refresh",
        "M17.65,6.35C16.2,4.9 14.21,4 12,4c-4.42,0 -7.99,3.58 -7.99,8s3.57,8 7.99,8c3.73,0 6.84,-2.55 7.73,-6h-2.08c-0.82,2.33 -3.04,4 -5.65,4 -3.31,0 -6,-2.69 -6,-6s2.69,-6 6,-6c1.66,0 3.14,0.69 4.22,1.78L13,11h7V4l-2.35,2.35z"
    )
    static let Check = icon("check", "M9,16.17L4.83,12l-1.42,1.41L9,19 21,7l-1.41,-1.41z")
    static let Map = icon(
        "map",
        "M20.5,3l-0.16,0.03L15,5.1 9,3 3.36,4.9c-0.21,0.07 -0.36,0.25 -0.36,0.48V20.5c0,0.28 0.22,0.5 0.5,0.5l0.16,-0.03L9,18.9l6,2.1 5.64,-1.9c0.21,-0.07 0.36,-0.25 0.36,-0.48V3.5c0,-0.28 -0.22,-0.5 -0.5,-0.5zM15,19l-6,-2.11V5l6,2.11V19z"
    )
    static let Trash = icon(
        "trash",
        "M6,19c0,1.1 0.9,2 2,2h8c1.1,0 2,-0.9 2,-2V7H6v12z",
        "M19,4h-3.5l-1,-1h-5l-1,1H5v2h14V4z"
    )
    static let Next = icon("next", "M10,6L8.59,7.41 13.17,12l-4.58,4.59L10,18l6,-6z")
}

// MARK: - Rendering

/// Material `Icon(imageVector, contentDescription, tint)`: fills its frame (square), like
/// `Modifier.size(x)` on Android — give it `.frame(width: x, height: x)`.
struct Icon: View {
    let imageVector: ImageVector
    let contentDescription: String?
    var tint: Color = .white

    init(_ imageVector: ImageVector, contentDescription: String?, tint: Color = .white) {
        self.imageVector = imageVector
        self.contentDescription = contentDescription
        self.tint = tint
    }

    var body: some View {
        let v = imageVector
        ZStack {
            ForEach(v.paths.indices, id: \.self) { i in
                VectorShape(path: v.paths[i].path, viewport: v.viewport)
                    .fill(tint, style: FillStyle(eoFill: v.paths[i].evenOdd, antialiased: true))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(idealWidth: 24, idealHeight: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(contentDescription ?? "")
        .accessibilityHidden(contentDescription == nil)
    }
}

/// One icon path scaled from its viewport into the shape's rect.
struct VectorShape: Shape {
    let path: Path
    var viewport: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / viewport, sy = rect.height / viewport
        return path.applying(CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: rect.minX, ty: rect.minY))
    }
}

extension GraphicsContext {
    /// Draws an icon into `rect` (Canvas use, e.g. icons inside custom drawings).
    func drawIcon(_ icon: ImageVector, in rect: CGRect, tint: Color) {
        let t = CGAffineTransform(a: rect.width / icon.viewport, b: 0, c: 0, d: rect.height / icon.viewport, tx: rect.minX, ty: rect.minY)
        for p in icon.paths {
            fill(p.path.applying(t), with: .color(tint), style: FillStyle(eoFill: p.evenOdd, antialiased: true))
        }
    }
}

// MARK: - SVG path data (Android `addPathNodes`)

/// Parser for SVG/Android path data: M L H V C S Q T Z (absolute and relative), with implicit repeats.
enum PathData {
    static func parse(_ d: String) -> Path {
        var path = Path()
        let chars = Array(d.utf8)
        var i = 0
        var cmd: UInt8 = 0
        var cur = CGPoint.zero
        var start = CGPoint.zero
        var lastCtrl: CGPoint?
        var lastQuad: CGPoint?

        func skipSeparators() {
            while i < chars.count, chars[i] == 32 || chars[i] == 44 || chars[i] == 10 || chars[i] == 13 || chars[i] == 9 { i += 1 }
        }

        func isNumberStart(_ c: UInt8) -> Bool { (c >= 48 && c <= 57) || c == 45 || c == 43 || c == 46 }

        func number() -> CGFloat {
            skipSeparators()
            let s = i
            if i < chars.count, chars[i] == 45 || chars[i] == 43 { i += 1 }
            var seenDot = false
            var seenExp = false
            while i < chars.count {
                let c = chars[i]
                if c >= 48 && c <= 57 { i += 1 }
                else if c == 46 && !seenDot && !seenExp { seenDot = true; i += 1 }
                else if (c == 101 || c == 69) && !seenExp {
                    seenExp = true
                    i += 1
                    if i < chars.count, chars[i] == 45 || chars[i] == 43 { i += 1 }
                } else { break }
            }
            let str = String(decoding: chars[s..<i], as: UTF8.self)
            return CGFloat(Double(str) ?? 0)
        }

        func point(_ rel: Bool) -> CGPoint {
            let x = number(), y = number()
            return rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
        }

        while true {
            skipSeparators()
            guard i < chars.count else { break }
            let c = chars[i]
            if !isNumberStart(c) {
                cmd = c
                i += 1
                if cmd == 90 || cmd == 122 { // Z z
                    path.closeSubpath()
                    cur = start
                    lastCtrl = nil
                    lastQuad = nil
                    continue
                }
            }
            let rel = cmd >= 97
            switch cmd {
            case 77, 109: // M m (following pairs are L/l)
                cur = point(rel)
                start = cur
                path.move(to: cur)
                cmd = rel ? 108 : 76
                lastCtrl = nil; lastQuad = nil
            case 76, 108: // L l
                cur = point(rel)
                path.addLine(to: cur)
                lastCtrl = nil; lastQuad = nil
            case 72, 104: // H h
                let x = number()
                cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y)
                path.addLine(to: cur)
                lastCtrl = nil; lastQuad = nil
            case 86, 118: // V v
                let y = number()
                cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y)
                path.addLine(to: cur)
                lastCtrl = nil; lastQuad = nil
            case 67, 99: // C c
                let c1 = point(rel), c2 = point(rel), e = point(rel)
                path.addCurve(to: e, control1: c1, control2: c2)
                lastCtrl = c2; lastQuad = nil
                cur = e
            case 83, 115: // S s
                let c1 = lastCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = point(rel), e = point(rel)
                path.addCurve(to: e, control1: c1, control2: c2)
                lastCtrl = c2; lastQuad = nil
                cur = e
            case 81, 113: // Q q
                let q = point(rel), e = point(rel)
                path.addQuadCurve(to: e, control: q)
                lastQuad = q; lastCtrl = nil
                cur = e
            case 84, 116: // T t
                let q = lastQuad.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let e = point(rel)
                path.addQuadCurve(to: e, control: q)
                lastQuad = q; lastCtrl = nil
                cur = e
            default:
                i += 1 // unknown token: skip
            }
        }
        return path
    }
}
