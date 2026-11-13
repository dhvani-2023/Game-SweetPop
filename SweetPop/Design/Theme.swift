import SwiftUI
import UIKit
import CoreText
import Observation
import GameKit

// MARK: - Font

/// Fredoka SemiBold is the only face. The bundled file is the SemiBold instance whose name table says
/// "Fredoka-Light", so that PostScript name is what we ask for.
enum SweetPopFonts {
    static let postScriptName = "Fredoka-Light"

    private static var registered = false
    private static let lock = NSLock()

    /// Registers the bundled font. Call once at launch, before any text is drawn.
    static func register() {
        lock.lock()
        defer { lock.unlock() }
        guard !registered else { return }
        registered = true
        FontRegistry.registerAll()
    }

    /// CoreText font for path rendering (outlined text, effect texts).
    static func ctFont(_ size: CGFloat) -> CTFont {
        CTFontCreateWithName(postScriptName as CFString, size, nil)
    }

    /// Text scale that `Font.custom(_:size:)` applies (Dynamic Type relative to `.body`), so path-rendered text
    /// (OutlinedText, effects) matches SwiftUI `Text` at every content size category.
    static func dynamicScale(_ dts: DynamicTypeSize) -> CGFloat {
        if dts == .large { return 1 }
        let traits = UITraitCollection(preferredContentSizeCategory: contentSizeCategory(dts))
        return UIFontMetrics(forTextStyle: .body).scaledValue(for: 100, compatibleWith: traits) / 100
    }

    private static func contentSizeCategory(_ d: DynamicTypeSize) -> UIContentSizeCategory {
        switch d {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

extension Font {
    /// Kotlin `TextStyle(fontFamily = Fredoka, fontWeight = SemiBold, fontSize = size.sp)`.
    static func fredoka(_ size: CGFloat) -> Font { .custom(SweetPopFonts.postScriptName, size: size) }
}

/// Type scale in sp (= pt) (spec 4.2).
enum TypeScale {
    static let Display: CGFloat = 64
    static let Title: CGFloat = 36
    static let Headline: CGFloat = 28
    static let Body: CGFloat = 18
    static let Label: CGFloat = 15
    static let Caption: CGFloat = 13
}

// MARK: - Palette in the environment (Kotlin LocalPalette)

private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette = LightPalette
}

extension EnvironmentValues {
    /// Kotlin `LocalPalette.current`.
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

enum ThemeMode {
    static let LIGHT = 0
    static let DARK = 1
    static let AUTO = 2
}

/// The system's light/dark setting. The app's Info.plist pins UIKit to Light, so the SwiftUI colour scheme
/// cannot be used for AUTO; the screen's trait collection still reports the real system setting.
@MainActor
@Observable
final class SystemAppearance {
    static let shared = SystemAppearance()

    private(set) var isDark: Bool = false

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        refresh()
        let nc = NotificationCenter.default
        for name in [UIApplication.didBecomeActiveNotification, UIApplication.willEnterForegroundNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { SystemAppearance.shared.refresh() }
            })
        }
    }

    func refresh() {
        let scene = UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
        guard let screen = scene?.screen else { return }
        let dark = screen.traitCollection.userInterfaceStyle == .dark
        if dark != isDark { isDark = dark }
    }
}

@MainActor
func isDarkFor(_ themeMode: Int) -> Bool {
    switch themeMode {
    case ThemeMode.DARK: return true
    case ThemeMode.AUTO: return SystemAppearance.shared.isDark
    default: return false
    }
}

/// Provides the palette to `content`. Every token animates (450 ms, Oklab) when the theme changes.
struct SweetPopTheme<Content: View>: View {
    let themeMode: Int
    let content: Content

    @State private var blend: Double?

    init(themeMode: Int = ThemeMode.LIGHT, @ViewBuilder content: () -> Content) {
        self.themeMode = themeMode
        self.content = content()
    }

    var body: some View {
        let dark = isDarkFor(themeMode)
        content
            .modifier(PaletteBlend(t: blend ?? (dark ? 1 : 0), isDark: dark))
            .onAppear {
                SystemAppearance.shared.refresh()
                if blend == nil { blend = dark ? 1 : 0 }
            }
            .onChange(of: dark) { _, now in
                // Kotlin: animateColorAsState(tween(450)) with FastOutSlowIn easing.
                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45)) { blend = now ? 1 : 0 }
            }
    }
}

private struct PaletteBlend: ViewModifier, Animatable {
    var t: Double
    let isDark: Bool

    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.palette, Palette.blend(Float(t), isDark: isDark))
            .environment(\.colorScheme, isDark ? .dark : .light)
    }
}

// MARK: - Brush (Compose Brush.verticalGradient for text)

/// Vertical gradient brush for text fills (Kotlin `Brush.verticalGradient(listOf(...))`): spans the text box.
struct Brush: Equatable {
    let colors: [Color]
    let gradient: Gradient

    static func verticalGradient(_ colors: [Color]) -> Brush { Brush(colors: colors, gradient: Gradient(colors: colors)) }

    static func == (a: Brush, b: Brush) -> Bool { a.colors == b.colors }
}

// MARK: - Text as paths (outlined text, floating effect texts)

/// A laid-out piece of text as glyph outlines. Origin is the top-left of the text box, y down.
final class TextPath {
    let path: Path
    let size: CGSize

    init(path: Path, size: CGSize) {
        self.path = path
        self.size = size
    }
}

/// CoreText layout of Fredoka text into paths, cached. Line metrics follow Android (`includeFontPadding = false`):
/// a line is ascent + descent tall; a custom `lineHeight` only changes the spacing between lines
/// (Compose's default `LineHeightStyle` trims the first line's top and the last line's bottom).
enum TextPaths {
    private static let cache: NSCache<NSString, TextPath> = {
        let c = NSCache<NSString, TextPath>()
        c.countLimit = 400
        return c
    }()

    static func layout(
        _ text: String, fontSize: CGFloat, maxWidth: CGFloat = .infinity, maxLines: Int = Int.max,
        lineHeight: CGFloat? = nil, align: TextAlignment = .center
    ) -> TextPath {
        let w = maxWidth.isFinite ? (maxWidth * 2).rounded(.down) / 2 : -1
        let alignKey: Int = align == .leading ? 0 : (align == .trailing ? 2 : 1)
        let key = "\(fontSize)|\(w)|\(maxLines)|\(lineHeight ?? -1)|\(alignKey)|\(text)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let tp = build(text, fontSize: fontSize, maxWidth: w < 0 ? .infinity : w, maxLines: maxLines,
                       lineHeight: lineHeight, align: align)
        cache.setObject(tp, forKey: key)
        return tp
    }

    private static func build(
        _ text: String, fontSize: CGFloat, maxWidth: CGFloat, maxLines: Int, lineHeight: CGFloat?, align: TextAlignment
    ) -> TextPath {
        let font = SweetPopFonts.ctFont(fontSize)
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let attr = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let length = attr.length
        guard length > 0 else { return TextPath(path: Path(), size: CGSize(width: 0, height: ascent + descent)) }
        let typesetter = CTTypesetterCreateWithAttributedString(attr)
        let breakWidth = maxWidth.isFinite ? Double(max(1, maxWidth + 0.5)) : 1e7

        var lines: [(line: CTLine, width: CGFloat)] = []
        var start = 0
        while start < length && lines.count < max(1, maxLines) {
            var count = CTTypesetterSuggestLineBreak(typesetter, start, breakWidth)
            if count <= 0 { count = length - start }
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line))
            lines.append((line, max(0, width)))
            start += count
        }

        let advance = lineHeight ?? (ascent + descent)
        let boxWidth = lines.reduce(CGFloat(0)) { max($0, $1.width) }
        let boxHeight = ascent + descent + advance * CGFloat(max(0, lines.count - 1))
        let path = CGMutablePath()
        for (i, l) in lines.enumerated() {
            let baseline = ascent + advance * CGFloat(i)
            let x0: CGFloat
            switch align {
            case .leading: x0 = 0
            case .trailing: x0 = boxWidth - l.width
            default: x0 = (boxWidth - l.width) / 2
            }
            guard let runs = CTLineGetGlyphRuns(l.line) as? [CTRun] else { continue }
            for run in runs {
                let n = CTRunGetGlyphCount(run)
                guard n > 0 else { continue }
                let attrs = CTRunGetAttributes(run) as NSDictionary
                let runFontRef = attrs[kCTFontAttributeName as String]
                let runFont = runFontRef.map { $0 as! CTFont } ?? font
                var glyphs = [CGGlyph](repeating: 0, count: n)
                var positions = [CGPoint](repeating: .zero, count: n)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                for k in 0..<n {
                    guard let g = CTFontCreatePathForGlyph(runFont, glyphs[k], nil) else { continue }
                    let t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x0 + positions[k].x, ty: baseline - positions[k].y)
                    path.addPath(g, transform: t)
                }
            }
        }
        return TextPath(path: Path(path), size: CGSize(width: ceil(boxWidth * 2) / 2, height: boxHeight))
    }
}

/// Converts an Android blur radius (Paint.setShadowLayer / Compose `Shadow.blurRadius`, in dp) to the
/// Gaussian sigma SwiftUI shadows use as their radius (Skia: sigma = 0.57735 × radius + 0.5 px).
@inline(__always)
func androidBlurSigma(_ radiusDp: CGFloat) -> CGFloat { radiusDp * 0.57735 + 0.18 }
