import SwiftUI
import GameKit

/// Colour tokens of the "Candy Pop" design system (spec section 4.1).
/// Read the current (animated) palette with `@Environment(\.palette)` — the iOS form of `LocalPalette.current`.
struct Palette: Equatable {
    let isDark: Bool
    let bgTop: Color
    let bgBottom: Color
    let panel: Color
    let panelAlt: Color
    let text: Color
    let subText: Color
    let accent: Color
    let accent2: Color
    let success: Color
    let danger: Color
    let gold: Color
    let sky: Color
    let mint: Color
    let hudBar: Color
    let hudBarDark: Color
    let cardBorder: Color
    let chipBg: Color
    let onBg: Color
    let onBgOutline: Color
    let overlay: Color
    let divider: Color
    let rays: Color
    let boardTile: Color
    let boardTileAlt: Color
    let boardBorder: Color
    let toggleOff: Color
}

let LightPalette = Palette(
    isDark: false,
    bgTop: Color(argb: 0xFFFF6FB1),
    bgBottom: Color(argb: 0xFF8B4DFF),
    panel: Color(argb: 0xFFFFFFFF),
    panelAlt: Color(argb: 0xFFFFF1F8),
    text: Color(argb: 0xFF4A1C6E),
    subText: Color(argb: 0xFF9D72BE),
    accent: Color(argb: 0xFFFF3D8B),
    accent2: Color(argb: 0xFF7B4DFF),
    success: Color(argb: 0xFF2BCB72),
    danger: Color(argb: 0xFFFF4D63),
    gold: Color(argb: 0xFFFFC12E),
    sky: Color(argb: 0xFF35B6FF),
    mint: Color(argb: 0xFF26D9A6),
    hudBar: Color(argb: 0xFF7A3FE6),
    hudBarDark: Color(argb: 0xFF5B27BF),
    cardBorder: Color(argb: 0xFFFFC9E5),
    chipBg: copyAlpha(0xFF2B0A4A, 0.32),
    onBg: .white,
    onBgOutline: Color(argb: 0xFF5A1A7E),
    overlay: copyAlpha(0xFF2A0B3D, 0.68),
    divider: Color(argb: 0xFFF3E3F6),
    rays: copyAlpha(0xFFFFFFFF, 0.11),
    boardTile: copyAlpha(0xFF26306E, 0.72),
    boardTileAlt: copyAlpha(0xFF2F3A82, 0.72),
    boardBorder: Color(argb: 0xFFFFF4FA),
    toggleOff: Color(argb: 0xFFE3D3F2)
)

let DarkPalette = Palette(
    isDark: true,
    bgTop: Color(argb: 0xFF2E1563),
    bgBottom: Color(argb: 0xFF0D0A26),
    panel: Color(argb: 0xFF281D50),
    panelAlt: Color(argb: 0xFF33266A),
    text: Color(argb: 0xFFFFFFFF),
    subText: Color(argb: 0xFFB4A4E2),
    accent: Color(argb: 0xFFFF4FA3),
    accent2: Color(argb: 0xFF8D6BFF),
    success: Color(argb: 0xFF2FD48A),
    danger: Color(argb: 0xFFFF5C72),
    gold: Color(argb: 0xFFFFC83A),
    sky: Color(argb: 0xFF3FC8FF),
    mint: Color(argb: 0xFF2FE3B0),
    hudBar: Color(argb: 0xFF3D2C82),
    hudBarDark: Color(argb: 0xFF2A1D63),
    cardBorder: Color(argb: 0xFF5A47A8),
    chipBg: copyAlpha(0xFF000000, 0.35),
    onBg: .white,
    onBgOutline: Color(argb: 0xFF150833),
    overlay: copyAlpha(0xFF05020C, 0.74),
    divider: Color(argb: 0xFF3B2E70),
    rays: copyAlpha(0xFFB89CFF, 0.07),
    boardTile: copyAlpha(0xFF0B0D24, 0.78),
    boardTileAlt: copyAlpha(0xFF14173A, 0.78),
    boardBorder: Color(argb: 0xFF8E6FD6),
    toggleOff: Color(argb: 0xFF4A3E78)
)

/// Kotlin `Color(0xFF…).copy(alpha = a)`: Compose stores sRGB colours as 8-bit ARGB, so the alpha is quantised.
private func copyAlpha(_ argb: UInt32, _ alpha: Float) -> Color {
    srgbColor(RGBA(argb: argb).with(alpha: alpha))
}

/// Shared accent colours that do not change with the theme.
enum CandyColors {
    static let nodeDone = Color(argb: 0xFFFF73AD)
    static let nodeTricky = Color(argb: 0xFF9B5CFF)
    static let nodeLocked = Color(argb: 0xFFB9A9D6)
    static let nodeLockedDark = Color(argb: 0xFF6D6196)
    static let orange = Color(argb: 0xFFFF8C1A)
    static let brown = Color(argb: 0xFF7A3A12)
}

// MARK: - Colour maths (Compose semantics)

/// sRGB-encoded colour components 0…1, like Compose `Color.red/green/blue/alpha`.
struct RGBA: Hashable {
    var r: Float
    var g: Float
    var b: Float
    var a: Float

    init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// From an Android `0xAARRGGBB` literal.
    init(argb: UInt32) {
        a = Float((argb >> 24) & 0xFF) / 255
        r = Float((argb >> 16) & 0xFF) / 255
        g = Float((argb >> 8) & 0xFF) / 255
        b = Float(argb & 0xFF) / 255
    }

    /// Resolves a SwiftUI colour (sRGB, gamma encoded).
    init(_ color: Color) {
        let c = color.resolve(in: colorResolveEnvironment)
        r = c.red
        g = c.green
        b = c.blue
        a = c.opacity
    }

    func with(alpha: Float) -> RGBA { RGBA(r, g, b, alpha) }

    /// Compose quantises sRGB colours to 8 bits per channel (`(x * 255f + 0.5f).toInt()`).
    var quantized: RGBA {
        @inline(__always) func q(_ x: Float) -> Float { Float(Int(x.coerceIn(0, 1) * 255 + 0.5)) / 255 }
        return RGBA(q(r), q(g), q(b), q(a))
    }

    var color: Color { Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a)) }

    /// GraphicsContext shading with this colour at `alpha` (Kotlin `color.copy(alpha = alpha)`), no `Color` allocation.
    @inline(__always)
    func shading(alpha: Float) -> GraphicsContext.Shading {
        .color(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: Double(alpha.coerceIn(0, 1)))
    }

    @inline(__always)
    var shading: GraphicsContext.Shading { shading(alpha: a) }

    static let white = RGBA(1, 1, 1, 1)
    static let black = RGBA(0, 0, 0, 1)
    static let transparent = RGBA(0, 0, 0, 0)
}

let colorResolveEnvironment = EnvironmentValues()

/// Builds a Compose-style sRGB colour (8-bit quantised).
@inline(__always)
func srgbColor(_ c: RGBA) -> Color { c.quantized.color }

/**
 * HSV shade: multiplies V by [k]; when darkening also boosts saturation ×1.08.
 * Used for borders (0.72), button lips (0.68) and text outlines on buttons (0.5).
 */
func shade(_ color: Color, _ k: Float) -> Color { srgbColor(shadeRGBA(RGBA(color), k)) }

func shadeRGBA(_ c: RGBA, _ k: Float) -> RGBA {
    let hsv = rgbToHsv(c.r, c.g, c.b)
    let s = k < 1 ? min(1, hsv.1 * 1.08) : hsv.1
    let v = (hsv.2 * k).coerceIn(0, 1)
    return hsvRGBA(hsv.0, s, v, c.a)
}

/// Mixes [color] towards white by [amount] (0..1). Compose `lerp` interpolates in Oklab.
func lighten(_ color: Color, _ amount: Float) -> Color { srgbColor(lightenRGBA(RGBA(color), amount)) }

func lightenRGBA(_ c: RGBA, _ amount: Float) -> RGBA {
    lerpRGBA(c, RGBA(1, 1, 1, c.a), amount.coerceIn(0, 1)).quantized
}

/// Hue in 0..360, saturation & value 0..1.
func hsvColor(_ h: Float, _ s: Float, _ v: Float, _ alpha: Float = 1) -> Color {
    srgbColor(hsvRGBA(h, s, v, alpha))
}

func hsvRGBA(_ h: Float, _ s: Float, _ v: Float, _ alpha: Float = 1) -> RGBA {
    let hh = fmodf(fmodf(h, 360) + 360, 360)
    let c = v * s
    let x = c * (1 - abs(fmodf(hh / 60, 2) - 1))
    let m = v - c
    let r: Float, g: Float, b: Float
    if hh < 60 { (r, g, b) = (c, x, 0) }
    else if hh < 120 { (r, g, b) = (x, c, 0) }
    else if hh < 180 { (r, g, b) = (0, c, x) }
    else if hh < 240 { (r, g, b) = (0, x, c) }
    else if hh < 300 { (r, g, b) = (x, 0, c) }
    else { (r, g, b) = (c, 0, x) }
    return RGBA(r + m, g + m, b + m, alpha).quantized
}

private func rgbToHsv(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
    let mx = max(r, max(g, b))
    let mn = min(r, min(g, b))
    let d = mx - mn
    let h: Float
    if d == 0 { h = 0 }
    else if mx == r { h = 60 * fmodf((g - b) / d, 6) }
    else if mx == g { h = 60 * (((b - r) / d) + 2) }
    else { h = 60 * (((r - g) / d) + 4) }
    let s: Float = mx == 0 ? 0 : d / mx
    return (fmodf(h + 360, 360), s, mx)
}

/// Compose `lerp(Color, Color, Float)`: interpolates in Oklab and converts back to sRGB.
func lerp(_ start: Color, _ stop: Color, _ fraction: Float) -> Color {
    srgbColor(lerpRGBA(RGBA(start), RGBA(stop), fraction))
}

func lerpRGBA(_ start: RGBA, _ stop: RGBA, _ t: Float) -> RGBA {
    let a = Oklab(start), b = Oklab(stop)
    let L = a.L + (b.L - a.L) * t
    let A = a.A + (b.A - a.A) * t
    let B = a.B + (b.B - a.B) * t
    let alpha = (start.a + (stop.a - start.a) * t).coerceIn(0, 1)
    return Oklab(L: L, A: A, B: B).rgba(alpha: alpha)
}

/// Oklab (Björn Ottosson) from/to sRGB, as used by Compose colour interpolation and colour animations.
struct Oklab {
    var L: Float
    var A: Float
    var B: Float

    init(L: Float, A: Float, B: Float) {
        self.L = L
        self.A = A
        self.B = B
    }

    init(_ c: RGBA) {
        let r = Oklab.toLinear(c.r), g = Oklab.toLinear(c.g), b = Oklab.toLinear(c.b)
        let l = cbrtf(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrtf(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrtf(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    func rgba(alpha: Float) -> RGBA {
        let L = self.L.coerceIn(0, 1), A = self.A.coerceIn(-0.5, 0.5), B = self.B.coerceIn(-0.5, 0.5)
        let l_ = L + 0.3963377774 * A + 0.2158037573 * B
        let m_ = L - 0.1055613458 * A - 0.0638541728 * B
        let s_ = L - 0.0894841775 * A - 1.2914855480 * B
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return RGBA(Oklab.toSrgb(r), Oklab.toSrgb(g), Oklab.toSrgb(b), alpha)
    }

    @inline(__always)
    static func toLinear(_ x: Float) -> Float {
        x >= 0.04045 ? powf((x + 0.055) / 1.055, 2.4) : x / 12.92
    }

    @inline(__always)
    static func toSrgb(_ x: Float) -> Float {
        let v = x >= 0.0031308 ? 1.055 * powf(x, 1 / 2.4) - 0.055 : 12.92 * x
        return v.coerceIn(0, 1)
    }
}

extension Palette {
    /// Every token interpolated (Oklab) from Light (t = 0) to Dark (t = 1); `isDark` is the target, not animated.
    static func blend(_ t: Float, isDark: Bool) -> Palette {
        if t <= 0 && !isDark { return LightPalette }
        if t >= 1 && isDark { return DarkPalette }
        let a = LightPalette, b = DarkPalette
        func l(_ x: Color, _ y: Color) -> Color { lerp(x, y, t.coerceIn(0, 1)) }
        return Palette(
            isDark: isDark,
            bgTop: l(a.bgTop, b.bgTop),
            bgBottom: l(a.bgBottom, b.bgBottom),
            panel: l(a.panel, b.panel),
            panelAlt: l(a.panelAlt, b.panelAlt),
            text: l(a.text, b.text),
            subText: l(a.subText, b.subText),
            accent: l(a.accent, b.accent),
            accent2: l(a.accent2, b.accent2),
            success: l(a.success, b.success),
            danger: l(a.danger, b.danger),
            gold: l(a.gold, b.gold),
            sky: l(a.sky, b.sky),
            mint: l(a.mint, b.mint),
            hudBar: l(a.hudBar, b.hudBar),
            hudBarDark: l(a.hudBarDark, b.hudBarDark),
            cardBorder: l(a.cardBorder, b.cardBorder),
            chipBg: l(a.chipBg, b.chipBg),
            onBg: l(a.onBg, b.onBg),
            onBgOutline: l(a.onBgOutline, b.onBgOutline),
            overlay: l(a.overlay, b.overlay),
            divider: l(a.divider, b.divider),
            rays: l(a.rays, b.rays),
            boardTile: l(a.boardTile, b.boardTile),
            boardTileAlt: l(a.boardTileAlt, b.boardTileAlt),
            boardBorder: l(a.boardBorder, b.boardBorder),
            toggleOff: l(a.toggleOff, b.toggleOff)
        )
    }
}
