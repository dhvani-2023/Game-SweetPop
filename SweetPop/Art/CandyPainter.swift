import SwiftUI
import CoreGraphics
import GameKit

/**
 * Renders candies per pixel from signed-distance shapes (spec section 6): soft drop shadow, dark outline,
 * gradient body with rim darkening and reflected light, then a specular highlight.
 * Normalised coordinates: a candy spans p ∈ [−1, 1]², y up; one unit = 0.45 × cell so the candy fills 90 %.
 *
 * iOS: renders straight into a premultiplied BGRA `CGImage` at the requested pixel size (cell points ×
 * display scale), rows split across cores. The shading maths is the Kotlin code, operation for operation.
 */
enum CandyPainter {
    private static let UNIT_FRAC: Float = 0.45
    private static let BITMAP_FRAC: Float = 1.2

    /// Bitmap edge length used for a candy drawn in a cell of [cellPx] pixels.
    static func bitmapSize(_ cellPx: Int) -> Int { Kt.toInt((Float(cellPx) * BITMAP_FRAC).rounded(.up)).coerceAtLeast(4) }

    /// Renders one candy. `parallel` splits the rows over all cores (single on-demand renders);
    /// `CandyArt.prewarm` renders many candies at once and runs each one serially instead.
    static func render(_ color: CandyColor, _ special: SpecialType, _ cellPx: Int, parallel: Bool = true) -> CGImage {
        let bs = bitmapSize(cellPx)
        let u = Float(cellPx) * UNIT_FRAC
        let c = Float(bs) / 2
        let aa = 1 / u
        var out = [UInt32](repeating: 0, count: bs * bs)
        out.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            let rows: (Int, Int) -> Void = { j0, j1 in
                var shader = Shader(color, special, aa)
                for j in j0..<j1 {
                    let y = -(Float(j) + 0.5 - c) / u
                    let row = base + j * bs
                    for i in 0..<bs {
                        let x = (Float(i) + 0.5 - c) / u
                        row[i] = shader.shade(x, y)
                    }
                }
            }
            if parallel {
                let bands = min(bs, max(1, ProcessInfo.processInfo.activeProcessorCount * 2))
                DispatchQueue.concurrentPerform(iterations: bands) { b in
                    rows(b * bs / bands, (b + 1) * bs / bands)
                }
            } else {
                rows(0, bs)
            }
        }
        return makeImage(out, bs)
    }

    /// ARGB ints (premultiplied, like an Android ARGB_8888 bitmap after setPixels) → CGImage.
    /// Little-endian 32-bit premultiplied-first is BGRA in memory: the native iOS layout, uploaded without conversion.
    private static func makeImage(_ px: [UInt32], _ bs: Int) -> CGImage {
        let data = px.withUnsafeBufferPointer { Data(buffer: $0) } as CFData
        let provider = CGDataProvider(data: data)!
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(
            width: bs, height: bs, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bs * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )!
    }

    // ------------------------------------------------------------------ SDF helpers

    @inline(__always)
    fileprivate static func clamp01(_ x: Float) -> Float { x < 0 ? 0 : (x > 1 ? 1 : x) }

    @inline(__always)
    fileprivate static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = clamp01((x - e0) / (e1 - e0))
        return t * t * (3 - 2 * t)
    }

    @inline(__always)
    fileprivate static func len(_ x: Float, _ y: Float) -> Float { (x * x + y * y).squareRoot() }

    @inline(__always)
    fileprivate static func smin(_ a: Float, _ b: Float, _ k: Float) -> Float {
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k * 0.25
    }

    @inline(__always)
    fileprivate static func sdCircle(_ x: Float, _ y: Float, _ r: Float) -> Float { len(x, y) - r }

    @inline(__always)
    fileprivate static func sdRoundBox(_ x: Float, _ y: Float, _ hx: Float, _ hy: Float, _ r: Float) -> Float {
        let qx = abs(x) - (hx - r)
        let qy = abs(y) - (hy - r)
        return len(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r
    }

    @inline(__always)
    fileprivate static func sdSegment(_ x: Float, _ y: Float, _ ax: Float, _ ay: Float, _ bx: Float, _ by: Float, _ r: Float) -> Float {
        let pax = x - ax
        let pay = y - ay
        let bax = bx - ax
        let bay = by - ay
        let h = clamp01((pax * bax + pay * bay) / (bax * bax + bay * bay))
        return len(pax - bax * h, pay - bay * h) - r
    }

    @inline(__always)
    fileprivate static func sdEllipse(_ x: Float, _ y: Float, _ rx: Float, _ ry: Float) -> Float {
        let k0 = len(x / rx, y / ry)
        let k1 = len(x / (rx * rx), y / (ry * ry))
        return k1 < 1e-5 ? -min(rx, ry) : k0 * (k0 - 1) / k1
    }

    /// Two circles joined by their external tangents (teardrop). p is relative to the big circle.
    @inline(__always)
    fileprivate static func sdUnevenCapsule(_ px: Float, _ py: Float, _ r1: Float, _ r2: Float, _ h: Float) -> Float {
        let x = abs(px)
        let b = (r1 - r2) / h
        let a = (1 - b * b).squareRoot()
        let k = x * -b + py * a
        if k < 0 { return len(x, py) - r1 }
        if k > a * h { return len(x, py - h) - r2 }
        return x * a + py * b - r1
    }

    @inline(__always)
    fileprivate static func sign(_ x: Float) -> Float { x > 0 ? 1 : (x < 0 ? -1 : x) }

    fileprivate static func sdTriangle(_ px: Float, _ py: Float, _ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) -> Float {
        let e0x = x1 - x0, e0y = y1 - y0
        let e1x = x2 - x1, e1y = y2 - y1
        let e2x = x0 - x2, e2y = y0 - y2
        let v0x = px - x0, v0y = py - y0
        let v1x = px - x1, v1y = py - y1
        let v2x = px - x2, v2y = py - y2
        let h0 = clamp01((v0x * e0x + v0y * e0y) / (e0x * e0x + e0y * e0y))
        let h1 = clamp01((v1x * e1x + v1y * e1y) / (e1x * e1x + e1y * e1y))
        let h2 = clamp01((v2x * e2x + v2y * e2y) / (e2x * e2x + e2y * e2y))
        let q0x = v0x - e0x * h0, q0y = v0y - e0y * h0
        let q1x = v1x - e1x * h1, q1y = v1y - e1y * h1
        let q2x = v2x - e2x * h2, q2y = v2y - e2y * h2
        let s = sign(e0x * e2y - e0y * e2x)
        let dx = min(min(q0x * q0x + q0y * q0y, q1x * q1x + q1y * q1y), q2x * q2x + q2y * q2y)
        let dy = min(min(s * (v0x * e0y - v0y * e0x), s * (v1x * e1y - v1y * e1x)), s * (v2x * e2y - v2y * e2x))
        return -dx.squareRoot() * sign(dy)
    }

    /// Body silhouette for each colour (spec 6.2).
    @inline(__always)
    fileprivate static func sdShape(_ color: CandyColor, _ x: Float, _ y: Float) -> Float {
        switch color {
        case .RED: return sdSegment(x, y, -0.42, -0.24, 0.42, 0.24, 0.42)
        case .ORANGE: return smin(sdEllipse(x, y, 0.84, 0.62), sdRoundBox(x, y, 0.62, 0.56, 0.3), 0.14)
        case .YELLOW: return sdUnevenCapsule(x, y + 0.30, 0.58, 0.16, 0.92)
        case .GREEN: return sdRoundBox(x, y, 0.70, 0.70, 0.26)
        case .BLUE: return sdCircle(x, y, 0.80)
        case .PURPLE:
            let r = len(x, y)
            let th = Kt.atan2(y, x)
            let rr = 0.68 + 0.14 * Kt.cos(5 * th)
            let dr = -0.70 * Kt.sin(5 * th)
            let f = r - rr
            return r < 1e-4 ? -rr : f / (1 + (dr / r) * (dr / r)).squareRoot()
        case .NONE: return sdCircle(x, y, 0.80)
        }
    }

    fileprivate static func sdWrapper(_ x: Float, _ y: Float) -> Float {
        let box = sdRoundBox(x, y, 0.66, 0.66, 0.2)
        let bow = sdTriangle(abs(x), y, 0.55, 0, 1.0, 0.36, 1.0, -0.36) - 0.05
        return smin(box, bow, 0.08)
    }

    // ------------------------------------------------------------------ per-pixel shader

    fileprivate struct Sprinkle {
        let x: Float, y: Float, dx: Float, dy: Float, r: Float, g: Float, b: Float
    }

    fileprivate static let sprinkles: [Sprinkle] = {
        let rnd = JavaRandom(5)
        let cols: [Int64] = [0xFFF52945, 0xFFFF8C1A, 0xFFFFD629, 0xFF38CC52, 0xFF338FFF, 0xFFAD4DF5, 0xFFFFFFFF, 0xFFFF8CC7]
        var out: [Sprinkle] = []
        var tries = 0
        while out.count < 26 && tries < 4000 {
            tries += 1
            let x = rnd.nextFloat() * 1.4 - 0.7
            let y = rnd.nextFloat() * 1.4 - 0.7
            if len(x, y) > 0.66 { continue }
            if out.contains(where: { len($0.x - x, $0.y - y) < 0.2 }) { continue }
            let a = rnd.nextFloat() * Float(Double.pi)
            let c = cols[out.count % cols.count]
            out.append(Sprinkle(
                x: x, y: y, dx: Kt.cos(a) * 0.08, dy: Kt.sin(a) * 0.08,
                r: Float((c >> 16) & 0xFF) / 255, g: Float((c >> 8) & 0xFF) / 255, b: Float(c & 0xFF) / 255
            ))
        }
        return out
    }()

    fileprivate struct Shader {
        let color: CandyColor
        let special: SpecialType
        let aa: Float
        let isBomb: Bool
        let isStriped: Bool
        let br: Float
        let bg: Float
        let bb: Float
        let sprinkles: [Sprinkle]

        // Accumulated premultiplied colour.
        var r: Float = 0
        var g: Float = 0
        var b: Float = 0
        var a: Float = 0

        // Scratch body colour.
        var cr: Float = 0
        var cg: Float = 0
        var cb: Float = 0

        init(_ color: CandyColor, _ special: SpecialType, _ aa: Float) {
            self.color = color
            self.special = special
            self.aa = aa
            isBomb = special == .COLOR_BOMB
            isStriped = special.isStriped
            let baseColor: CandyColor = isBomb ? .NONE : color
            let argb = baseColor.argb
            br = Float((argb >> 16) & 0xFF) / 255
            bg = Float((argb >> 8) & 0xFF) / 255
            bb = Float(argb & 0xFF) / 255
            sprinkles = isBomb ? CandyPainter.sprinkles : []
        }

        @inline(__always)
        private mutating func over(_ sr: Float, _ sg: Float, _ sb: Float, _ sa: Float) {
            if sa <= 0 { return }
            let k = 1 - sa
            r = sr * sa + r * k
            g = sg * sa + g * k
            b = sb * sa + b * k
            a = sa + a * k
        }

        @inline(__always)
        private func coverage(_ d: Float) -> Float { clamp01(0.5 - d / aa) }

        /// Returns the pixel as Android ARGB int, premultiplied the way `Bitmap.setPixels` stores it.
        mutating func shade(_ x: Float, _ y: Float) -> UInt32 {
            r = 0; g = 0; b = 0; a = 0
            if special == .WRAPPED { shadeWrapped(x, y) } else { shadeSimple(x, y) }
            if a <= 0.002 { return 0 }
            let ia = 1 / a
            let ai = Kt.roundToInt(a * 255).coerceIn(0, 255)
            var ri = Kt.roundToInt(r * ia * 255).coerceIn(0, 255)
            var gi = Kt.roundToInt(g * ia * 255).coerceIn(0, 255)
            var bi = Kt.roundToInt(b * ia * 255).coerceIn(0, 255)
            if ai != 255 {
                // Skia SkPremultiplyARGBInline / SkMulDiv255Round.
                ri = mulDiv255Round(ri, ai)
                gi = mulDiv255Round(gi, ai)
                bi = mulDiv255Round(bi, ai)
            }
            return UInt32(ai) << 24 | UInt32(ri) << 16 | UInt32(gi) << 8 | UInt32(bi)
        }

        @inline(__always)
        private func mulDiv255Round(_ v: Int, _ a: Int) -> Int {
            let prod = v * a + 128
            return (prod + (prod >> 8)) >> 8
        }

        @inline(__always)
        private func silhouette(_ x: Float, _ y: Float) -> Float {
            isBomb ? sdCircle(x, y, 0.8) : sdShape(color, x, y)
        }

        @inline(__always)
        private mutating func shadow(_ d: Float) {
            over(0, 0, 0, 0.35 * (1 - smoothstep(-0.08, 0.08, d)))
        }

        private mutating func shadeSimple(_ x: Float, _ y: Float) {
            let d = silhouette(x, y)
            if d > 0.3 {
                shadow(silhouette(x - 0.02, y + 0.07))
                return
            }
            shadow(silhouette(x - 0.02, y + 0.07))
            over(br * 0.5, bg * 0.5, bb * 0.5, coverage(d - 0.03))
            let cov = coverage(d)
            if cov <= 0 { return }
            bodyColour(br, bg, bb, x, y, d)
            if isBomb { sprinklesOn(x, y) }
            specular(x, y, d, color == .RED && !isBomb ? 0.1 : 0)
            over(cr, cg, cb, cov)
        }

        private mutating func shadeWrapped(_ x: Float, _ y: Float) {
            let dw = sdWrapper(x, y)
            shadow(sdWrapper(x - 0.02, y + 0.07))
            // Wrapper: base lightened 28 %.
            let wr = br + (1 - br) * 0.28
            let wg = bg + (1 - bg) * 0.28
            let wb = bb + (1 - bb) * 0.28
            over(br * 0.5, bg * 0.5, bb * 0.5, coverage(dw - 0.03))
            let cw = coverage(dw)
            if cw > 0 {
                cr = wr; cg = wg; cb = wb
                gradient(wr, wg, wb, y)
                // Diagonal crinkle highlights.
                let cr1 = smoothstep(0.55, 0.9, Kt.sin((x - y) * 13 + 0.6))
                let cr2 = smoothstep(0.7, 0.95, Kt.sin((x + y) * 9 + 1.7)) * 0.5
                mixWhite((cr1 + cr2) * 0.32)
                rim(dw, wr, wg, wb)
                over(cr, cg, cb, cw)
            }
            // Inner candy at 62 % scale.
            let s: Float = 0.62
            let di = sdShape(color, x / s, y / s) * s
            over(br * 0.5, bg * 0.5, bb * 0.5, coverage(di - 0.03 * s))
            let ci = coverage(di)
            if ci > 0 {
                bodyColour(br, bg, bb, x / s, y / s, di / s)
                specular(x / s, y / s, di / s, color == .RED ? 0.1 : 0)
                over(cr, cg, cb, ci)
            }
        }

        @inline(__always)
        private mutating func gradient(_ r0: Float, _ g0: Float, _ b0: Float, _ y: Float) {
            let k = smoothstep(-0.95, 0.95, y)
            let tr = r0 + (1 - r0) * 0.22
            let tg = g0 + (1 - g0) * 0.22
            let tb = b0 + (1 - b0) * 0.22
            cr = r0 * 0.78 + (tr - r0 * 0.78) * k
            cg = g0 * 0.78 + (tg - g0 * 0.78) * k
            cb = b0 * 0.78 + (tb - b0 * 0.78) * k
        }

        @inline(__always)
        private mutating func mixWhite(_ t: Float) {
            if t <= 0 { return }
            cr += (1 - cr) * t
            cg += (1 - cg) * t
            cb += (1 - cb) * t
        }

        @inline(__always)
        private mutating func mixDark(_ k: Float, _ t: Float) {
            cr += (cr * k - cr) * t
            cg += (cg * k - cg) * t
            cb += (cb * k - cb) * t
        }

        /// Rim darkening towards base × 0.62 plus a little reflected light near the bottom edge.
        @inline(__always)
        private mutating func rim(_ d: Float, _ r0: Float, _ g0: Float, _ b0: Float) {
            let inside = -d
            let rimK = (1 - smoothstep(0, 0.24, inside)) * 0.75
            cr += (r0 * 0.62 - cr) * rimK
            cg += (g0 * 0.62 - cg) * rimK
            cb += (b0 * 0.62 - cb) * rimK
        }

        @inline(__always)
        private mutating func reflect(_ y: Float, _ d: Float) {
            let inside = -d
            let band = smoothstep(0.02, 0.07, inside) * (1 - smoothstep(0.09, 0.2, inside))
            mixWhite(band * smoothstep(-0.25, -0.85, y) * 0.22)
        }

        private mutating func bodyColour(_ r0: Float, _ g0: Float, _ b0: Float, _ x: Float, _ y: Float, _ d: Float) {
            gradient(r0, g0, b0, y)
            if !isBomb { pattern(x, y) }
            if isStriped {
                let axis = special == .STRIPED_H ? y : x
                mixWhite(smoothstep(0.02, 0.3, Kt.sin(axis * 20)) * 0.86)
            }
            rim(d, r0, g0, b0)
            reflect(y, d)
        }

        /// Per-shape surface details.
        private mutating func pattern(_ x: Float, _ y: Float) {
            switch color {
            case .ORANGE:
                let band = 1 - smoothstep(0.04, 0.075, abs(y))
                mixDark(0.8, band)
            case .GREEN:
                let d2 = sdRoundBox(x, y, 0.46, 0.46, 0.18)
                let inner = clamp01(0.5 - d2 / aa)
                mixWhite(inner * 0.16)
                let edge = 1 - smoothstep(0, 0.05, abs(d2))
                mixDark(0.85, edge * 0.5 * (y > 0 ? 0.4 : 1))
            case .BLUE:
                let rr = len(x, y)
                let th = Kt.atan2(y, x)
                let s = Kt.sin(3 * th + 9 * rr)
                let m = smoothstep(-0.12, 0.18, s) * smoothstep(0.02, 0.12, rr)
                mixWhite(m * 0.38)
            case .PURPLE:
                let dc = len(x, y) - 0.32
                let m = clamp01(0.5 - dc / aa)
                mixWhite(m * 0.3)
                let ring = 1 - smoothstep(0, 0.04, abs(dc))
                mixDark(0.8, ring * 0.45)
            default:
                break
            }
        }

        private mutating func sprinklesOn(_ x: Float, _ y: Float) {
            let light = 0.78 + 0.3 * smoothstep(-0.8, 0.8, y)
            for s in sprinkles {
                let d = sdSegment(x, y, s.x - s.dx, s.y - s.dy, s.x + s.dx, s.y + s.dy, 0.042)
                let cov = clamp01(0.5 - d / aa)
                if cov <= 0 { continue }
                let edge = 1 - smoothstep(0, 0.025, -d)
                var sr = s.r * light
                var sg = s.g * light
                var sb = s.b * light
                sr += (sr * 0.65 - sr) * edge
                sg += (sg * 0.65 - sg) * edge
                sb += (sb * 0.65 - sb) * edge
                cr += (sr - cr) * cov
                cg += (sg - cg) * cov
                cb += (sb - cb) * cov
            }
        }

        /// Specular ellipse (−0.26, 0.36), radii 0.34×0.16 rotated 28°, white 72 %; plus a small dot.
        private mutating func specular(_ x: Float, _ y: Float, _ d: Float, _ inset: Float) {
            let dx = x + 0.26 - inset
            let dy = y - 0.36 + inset
            let ca: Float = 0.8829 // cos 28°
            let sa: Float = 0.4695 // sin 28°
            let ex = dx * ca + dy * sa
            let ey = -dx * sa + dy * ca
            let e = (ex / 0.34) * (ex / 0.34) + (ey / 0.16) * (ey / 0.16)
            let clip = smoothstep(0, 0.05, -d)
            mixWhite((1 - smoothstep(0.55, 1.0, e)) * 0.72 * clip)
            let dd = len(x - 0.30, y + 0.36) - 0.06
            mixWhite(clamp01(0.5 - dd / aa) * 0.45 * clip)
        }
    }
}

// MARK: - Cache

/// Cache of rendered candy bitmaps keyed by (colour, special, pixel size).
enum CandyArt {
    private struct Entry {
        let cg: CGImage
        let image: Image
    }

    private static let lock = NSLock()
    private static var cache: [Int: Entry] = [:]
    private static var pending = Set<Int>()
    private static let background = DispatchQueue(label: "candy-art", qos: .userInitiated)

    private static func key(_ color: CandyColor, _ special: SpecialType, _ px: Int) -> Int {
        (px << 16) | (color.ordinal << 8) | special.ordinal
    }

    /// Every colour/special combination that exists in the game (6×4 + colour bomb = 25).
    static let allKinds: [(CandyColor, SpecialType)] =
        CandyColor.PLAYABLE.flatMap { c in
            [SpecialType.NONE, .STRIPED_H, .STRIPED_V, .WRAPPED].map { (c, $0) }
        } + [(CandyColor.NONE, SpecialType.COLOR_BOMB)]

    @inline(__always)
    private static func normalize(_ color: CandyColor, _ special: SpecialType, _ cellPx: Int) -> (CandyColor, Int) {
        (special == .COLOR_BOMB ? .NONE : color, cellPx.coerceIn(8, 512))
    }

    private static func entry(_ color: CandyColor, _ special: SpecialType, _ px: Int, parallel: Bool) -> Entry {
        let k = key(color, special, px)
        lock.lock()
        if let e = cache[k] { lock.unlock(); return e }
        lock.unlock()
        let cg = CandyPainter.render(color, special, px, parallel: parallel)
        let e = Entry(cg: cg, image: Image(decorative: cg, scale: 1).interpolation(.high).antialiased(true))
        lock.lock()
        defer { lock.unlock() }
        if let existing = cache[k] { return existing }
        cache[k] = e
        return e
    }

    /// Returns the bitmap, rendering it on the calling thread if needed.
    static func bitmap(_ color: CandyColor, _ special: SpecialType, _ cellPx: Int) -> CGImage {
        let (c, px) = normalize(color, special, cellPx)
        return entry(c, special, px, parallel: true).cg
    }

    /// Returns the image if it is cached; otherwise schedules it on a background queue and returns nil,
    /// so drawing never blocks the main thread (the candy appears a frame or two later).
    static func peek(_ color: CandyColor, _ special: SpecialType, _ cellPx: Int) -> Image? {
        let (c, px) = normalize(color, special, cellPx)
        let k = key(c, special, px)
        lock.lock()
        if let e = cache[k] { lock.unlock(); return e.image }
        let schedule = pending.insert(k).inserted
        lock.unlock()
        if schedule {
            background.async {
                _ = entry(c, special, px, parallel: true)
                lock.lock()
                pending.remove(k)
                lock.unlock()
            }
        }
        return nil
    }

    /**
     * What `drawCandy` uses. Exact size cached → that image. Otherwise the exact size is scheduled in the background
     * (like `peek`) and the nearest cached size of the same candy is returned to be scaled meanwhile (larger sizes
     * preferred), so static canvases never stay empty. Only when this candy has never been rendered at any size is
     * it rendered right here, once. (Android draws nothing until a later redraw in these cases.)
     */
    static func imageForDrawing(_ color: CandyColor, _ special: SpecialType, _ cellPx: Int) -> Image {
        let (c, px) = normalize(color, special, cellPx)
        let k = key(c, special, px)
        let kindBits = k & 0xFFFF
        lock.lock()
        if let e = cache[k] { lock.unlock(); return e.image }
        var above: (px: Int, image: Image)?
        var below: (px: Int, image: Image)?
        for (key, e) in cache where key & 0xFFFF == kindBits {
            let p = key >> 16
            if p > px { if above == nil || p < above!.px { above = (p, e.image) } }
            else if below == nil || p > below!.px { below = (p, e.image) }
        }
        let fallback = above?.image ?? below?.image
        let schedule = fallback != nil && pending.insert(k).inserted
        lock.unlock()
        if schedule {
            background.async {
                _ = entry(c, special, px, parallel: true)
                lock.lock()
                pending.remove(k)
                lock.unlock()
            }
        }
        if let fallback { return fallback }
        return entry(c, special, px, parallel: true).image
    }

    static func isReady(_ cellPx: Int) -> Bool {
        let px = cellPx.coerceIn(8, 512)
        lock.lock()
        defer { lock.unlock() }
        return allKinds.allSatisfy { cache[key($0.0, $0.1, px)] != nil }
    }

    /// Renders all 25 candies for a cell size, in parallel off the main thread. `onEach` runs on a worker thread.
    static func prewarm(_ cellPx: Int, onEach: @escaping @Sendable () -> Void = {}) async {
        let px = cellPx.coerceIn(8, 512)
        let kinds = allKinds
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                DispatchQueue.concurrentPerform(iterations: kinds.count) { i in
                    let (c, s) = kinds[i]
                    _ = entry(c, s, px, parallel: false)
                    onEach()
                }
                cont.resume()
            }
        }
    }

    /// Splash helper: prewarms several cell sizes, reporting overall progress 0…1 on the main actor.
    static func prewarm(sizes: [Int], onProgress: @escaping @MainActor @Sendable (Float) -> Void) async {
        let total = max(1, sizes.count * allKinds.count)
        let counter = ProgressCounter()
        for px in sizes {
            await prewarm(px) {
                let done = counter.increment()
                Task { @MainActor in onProgress(Float(done) / Float(total)) }
            }
        }
    }

    static func clear() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}

/// Thread-safe counter for progress callbacks from worker threads.
final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

/// Shared bitmap resolution for decorative candies (backdrop, map, icons, onboarding).
/// `density` is the display scale (pixels per point), like Android's density (pixels per dp).
func decorBitmapPx(_ density: CGFloat) -> Int { Kt.toInt(Float(56 * density)) }

extension GraphicsContext {
    /**
     * Draws a candy centred at ([cx], [cy]) for a cell of [cellPx] canvas units (points). [bitmapPx] picks the
     * cached resolution in pixels (defaults to the cell size × display scale, i.e. 1:1 device pixels);
     * the image is scaled to fit. Like Android, the destination is snapped to whole device pixels.
     * A size that is not cached yet is drawn from the nearest cached size until it is ready (see `imageForDrawing`).
     */
    func drawCandy(
        _ color: CandyColor, _ special: SpecialType, _ cx: CGFloat, _ cy: CGFloat, _ cellPx: CGFloat,
        scaleX: CGFloat = 1, scaleY: CGFloat = 1, alpha: CGFloat = 1, rotationDeg: CGFloat = 0, bitmapPx: Int? = nil
    ) {
        if alpha <= 0 || scaleX <= 0 || scaleY <= 0 || cellPx <= 0 { return }
        let scale = max(1, environment.displayScale)
        let bpx = bitmapPx ?? Kt.roundToInt(Double(cellPx * scale))
        guard bpx > 0 else { return }
        let img = CandyArt.imageForDrawing(color, special, bpx)
        let drawn = CGFloat(CandyPainter.bitmapSize(bpx)) * (cellPx / CGFloat(bpx))
        let w = drawn * scaleX
        let h = drawn * scaleY
        // IntOffset / IntSize in device pixels.
        let x0 = ((cx - w / 2) * scale).rounded() / scale
        let y0 = ((cy - h / 2) * scale).rounded() / scale
        let wd = max(1, (w * scale).rounded()) / scale
        let hd = max(1, (h * scale).rounded()) / scale
        var c = self
        c.opacity *= Double(min(1, alpha))
        if rotationDeg != 0 {
            c.translateBy(x: cx, y: cy)
            c.rotate(by: .degrees(Double(rotationDeg)))
            c.translateBy(x: -cx, y: -cy)
        }
        c.draw(img, in: CGRect(x: x0, y: y0, width: wd, height: hd))
    }
}
