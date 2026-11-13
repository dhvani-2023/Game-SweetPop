import SwiftUI
import GameKit

// Port notes (Compose → SwiftUI):
// • Kotlin `modifier` parameters are dropped: apply SwiftUI modifiers to the view instead.
// • Palette-dependent defaults (`LocalPalette.current.x`) are `nil` here and resolved from `@Environment(\.palette)`.
// • CandyCard, CandyButton3D and Segmented fill the width they are offered (Android call sites pass
//   `fillMaxWidth()` / `weight(1f)`); add `.fixedSize()` where Android wrapped content
//   (e.g. `.frame(minWidth: 230).fixedSize()` for `Modifier.widthIn(min = 230.dp)`).
// • Click sound + haptic come from `AudioManager.shared` / `Haptics.shared` (Kotlin LocalAudio / LocalHaptics).

private let Plum35 = srgbColor(RGBA(argb: 0xFF4A1C6E).with(alpha: 0.35))

/// Shared tap guard: taps within 120 ms of the previous accepted tap are ignored.
@MainActor
enum TapGuard {
    private static var last: Double = -1_000

    static func accept() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime * 1000
        if now - last < 120 { return false }
        last = now
        return true
    }
}

/// Compose `PaddingValues` helpers (start = leading, end = trailing).
func PaddingValues(_ all: CGFloat) -> EdgeInsets { EdgeInsets(top: all, leading: all, bottom: all, trailing: all) }
func PaddingValues(horizontal: CGFloat = 0, vertical: CGFloat = 0) -> EdgeInsets {
    EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
}
func PaddingValues(start: CGFloat = 0, top: CGFloat = 0, end: CGFloat = 0, bottom: CGFloat = 0) -> EdgeInsets {
    EdgeInsets(top: top, leading: start, bottom: bottom, trailing: end)
}

// ---------------------------------------------------------------- text

/// White text with a plum stroke underneath and a soft drop shadow.
/// Rendered from Fredoka glyph outlines: a real round-join stroke of `outlineWidth` around each glyph
/// (Android draws the text twice, stroke width 2 × outlineWidth, then the fill), optional vertical gradient
/// `brush` over the text box, and the text shadow (black 30 %, y 3, blur 6) on the stroke.
struct OutlinedText: View {
    let text: String
    var fontSize: CGFloat = TypeScale.Headline
    var color: Color = .white
    var brush: Brush? = nil
    /// nil = `LocalPalette.current.onBgOutline`.
    var outline: Color? = nil
    var outlineWidth: CGFloat = 3
    var shadow: Bool = true
    var textAlign: TextAlignment = .center
    var maxLines: Int = Int.max
    var lineHeight: CGFloat? = nil

    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        _ text: String, fontSize: CGFloat = TypeScale.Headline, color: Color = .white, brush: Brush? = nil,
        outline: Color? = nil, outlineWidth: CGFloat = 3, shadow: Bool = true, textAlign: TextAlignment = .center,
        maxLines: Int = Int.max, lineHeight: CGFloat? = nil
    ) {
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.brush = brush
        self.outline = outline
        self.outlineWidth = outlineWidth
        self.shadow = shadow
        self.textAlign = textAlign
        self.maxLines = maxLines
        self.lineHeight = lineHeight
    }

    var body: some View {
        let scale = SweetPopFonts.dynamicScale(dynamicTypeSize)
        let spec = OutlinedTextSpec(
            text: text, fontSize: fontSize * scale, maxLines: maxLines,
            lineHeight: lineHeight.map { $0 * scale }, align: textAlign
        )
        let outlineColor = outline ?? palette.onBgOutline
        let strokeWidth = outlineWidth
        let withShadow = shadow
        let fill = color
        let fillBrush = brush
        let pad = strokeWidth + (withShadow ? 14 : 2)
        OutlinedTextLayout(spec: spec, pad: pad) {
            Canvas { ctx, size in
                let boxW = size.width - pad * 2
                let tp = spec.layout(maxWidth: boxW)
                var c = ctx
                let dx: CGFloat
                switch spec.align {
                case .leading: dx = 0
                case .trailing: dx = boxW - tp.size.width
                default: dx = (boxW - tp.size.width) / 2
                }
                c.translateBy(x: pad + dx, y: pad)
                if strokeWidth > 0 {
                    var s = c
                    if withShadow {
                        s.addFilter(.shadow(color: srgbColor(RGBA(0, 0, 0, 0.3)), radius: androidBlurSigma(6), x: 0, y: 3))
                    }
                    s.stroke(tp.path, with: .color(outlineColor), style: StrokeStyle(lineWidth: strokeWidth * 2, lineJoin: .round))
                }
                if let fillBrush {
                    c.fill(tp.path, with: .linearGradient(fillBrush.gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: tp.size.height)))
                } else {
                    c.fill(tp.path, with: .color(fill))
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isStaticText)
    }
}

private struct OutlinedTextSpec: Equatable {
    let text: String
    let fontSize: CGFloat
    let maxLines: Int
    let lineHeight: CGFloat?
    let align: TextAlignment

    func layout(maxWidth: CGFloat) -> TextPath {
        TextPaths.layout(text, fontSize: fontSize, maxWidth: maxWidth, maxLines: maxLines, lineHeight: lineHeight, align: align)
    }
}

/// Sizes like `Text` (hugs its lines, wraps at the offered width) and gives its single subview (the drawing
/// canvas) `pad` extra room on every side for the stroke and shadow.
private struct OutlinedTextLayout: Layout {
    let spec: OutlinedTextSpec
    let pad: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        spec.layout(maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for s in subviews {
            s.place(
                at: CGPoint(x: bounds.minX - pad, y: bounds.minY - pad), anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width + pad * 2, height: bounds.height + pad * 2)
            )
        }
    }
}

let TitleGradient = Brush.verticalGradient([.white, Color(argb: 0xFFFFE0F4)])

/// Plain body text in Fredoka.
struct BodyText: View {
    let text: String
    /// nil = `LocalPalette.current.text`.
    var color: Color? = nil
    var fontSize: CGFloat = TypeScale.Body
    var textAlign: TextAlignment = .center

    @Environment(\.palette) private var palette

    init(_ text: String, color: Color? = nil, fontSize: CGFloat = TypeScale.Body, textAlign: TextAlignment = .center) {
        self.text = text
        self.color = color
        self.fontSize = fontSize
        self.textAlign = textAlign
    }

    var body: some View {
        Text(text)
            .font(.fredoka(fontSize))
            .foregroundStyle(color ?? palette.text)
            .multilineTextAlignment(textAlign)
    }
}

// ---------------------------------------------------------------- cards

/// Rounded card with a thick candy border, soft plum shadow and (for coloured cards) a top sheen.
/// Fills the offered width (Android call sites use `fillMaxWidth()`).
struct CandyCard<Content: View>: View {
    var color: Color? = nil
    var radius: CGFloat = 28
    var borderWidth: CGFloat = 7
    var contentPadding: EdgeInsets = PaddingValues(20)
    var horizontalAlignment: HorizontalAlignment = .center
    let content: Content

    @Environment(\.palette) private var p

    init(
        color: Color? = nil, radius: CGFloat = 28, borderWidth: CGFloat = 7, contentPadding: EdgeInsets = PaddingValues(20),
        horizontalAlignment: HorizontalAlignment = .center, @ViewBuilder content: () -> Content
    ) {
        self.color = color
        self.radius = radius
        self.borderWidth = borderWidth
        self.contentPadding = contentPadding
        self.horizontalAlignment = horizontalAlignment
        self.content = content()
    }

    var body: some View {
        let fill = color ?? p.panel
        let border = color.map { shade($0, 0.72) } ?? p.cardBorder
        let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
        VStack(alignment: horizontalAlignment, spacing: 0) { content }
            .padding(contentPadding)
            .padding(borderWidth)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: horizontalAlignment, vertical: .center))
            .background {
                ZStack {
                    fill
                    if color != nil {
                        // drawRect(white 16 %, size = (width, height / 2))
                        LinearGradient(stops: [
                            .init(color: srgbColor(RGBA(1, 1, 1, 0.16)), location: 0),
                            .init(color: srgbColor(RGBA(1, 1, 1, 0.16)), location: 0.5),
                            .init(color: .clear, location: 0.5),
                        ], startPoint: .top, endPoint: .bottom)
                    }
                }
            }
            .overlay { shape.strokeBorder(border, lineWidth: borderWidth) }
            .clipShape(shape)
            .background {
                // Modifier.shadow(12.dp, ambient/spot = plum 35 %): Android scales these by the theme's shadow alphas.
                shape.fill(fill).shadow(color: Plum35.opacity(0.3), radius: 8, x: 0, y: 6)
            }
    }
}

// ---------------------------------------------------------------- buttons

/// Kotlin `drawShine()`: white 32 % rounded bar across the top of a face.
private struct Shine: View {
    var alpha: Float = 0.32

    var body: some View {
        Canvas { ctx, size in
            let h = size.height
            let rect = CGRect(x: size.width * 0.08, y: h * 0.09, width: size.width * 0.84, height: h * 0.3)
            ctx.fill(Path(roundedRect: rect, cornerRadius: min(h * 0.15, rect.height / 2), style: .circular), with: RGBA.white.shading(alpha: alpha))
        }
        .allowsHitTesting(false)
    }
}

private extension View {
    /// Kotlin `infiniteRepeatable(tween(1500, EaseInOutSine), Reverse)` between 0.975 and 1.025.
    @ViewBuilder
    func breathing(_ on: Bool) -> some View {
        if on {
            phaseAnimator([CGFloat(0.975), CGFloat(1.025)]) { content, s in
                content.scaleEffect(s)
            } animation: { _ in
                .timingCurve(0.37, 0, 0.63, 1, duration: 1.5)
            }
        } else {
            self
        }
    }
}

/// Press animation of the 3D buttons: tween(60) down, spring(0.45, 600) back up.
private func pressAnimation(_ pressed: Bool) -> Animation {
    pressed ? .timingCurve(0.4, 0, 0.2, 1, duration: 0.06) : .compose(dampingRatio: 0.45, stiffness: 600)
}

/// Chunky 3D candy button: darker lip below, glossy face that presses down onto it.
struct CandyButton3D: View {
    let text: String
    let onClick: () -> Void
    /// nil = `LocalPalette.current.success`.
    var color: Color? = nil
    var height: CGFloat = 68
    var fontSize: CGFloat = 28
    var icon: ImageVector? = nil
    var enabled: Bool = true
    var breathing: Bool = false

    @Environment(\.palette) private var p
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        _ text: String, onClick: @escaping () -> Void, color: Color? = nil, height: CGFloat = 68, fontSize: CGFloat = 28,
        icon: ImageVector? = nil, enabled: Bool = true, breathing: Bool = false
    ) {
        self.text = text
        self.onClick = onClick
        self.color = color
        self.height = height
        self.fontSize = fontSize
        self.icon = icon
        self.enabled = enabled
        self.breathing = breathing
    }

    var body: some View {
        let c = enabled ? (color ?? p.success) : Color(argb: 0xFFB3A6C9)
        let enabled = self.enabled
        let onClick = self.onClick
        Button {
            if enabled && TapGuard.accept() {
                AudioManager.shared.play(.CLICK)
                Haptics.shared.light()
                onClick()
            }
        } label: {
            EmptyView()
        }
        .buttonStyle(Candy3DStyle(text: text, color: c, height: height, fontSize: fontSize, icon: icon))
        .disabled(!enabled)
        .accessibilityLabel(text)
        .breathing(breathing && !reduceMotion && !GameKit.Motion.reduce)
    }
}

private struct Candy3DStyle: ButtonStyle {
    let text: String
    let color: Color
    let height: CGFloat
    let fontSize: CGFloat
    let icon: ImageVector?

    func makeBody(configuration: Configuration) -> some View {
        Candy3DFace(text: text, color: color, height: height, fontSize: fontSize, icon: icon, pressed: configuration.isPressed)
    }
}

private struct Candy3DFace: View {
    let text: String
    let color: Color
    let height: CGFloat
    let fontSize: CGFloat
    let icon: ImageVector?
    let pressed: Bool

    var body: some View {
        let lip: CGFloat = 6
        let pressDepth: CGFloat = 5
        let shape = RoundedRectangle(cornerRadius: height / 2 * 0.6, style: .circular)
        HStack(spacing: 0) {
            if let icon {
                Icon(icon, contentDescription: nil, tint: .white)
                    .frame(width: height * 0.38, height: height * 0.38)
                Spacer().frame(width: 6)
            }
            OutlinedText(text, fontSize: fontSize, outline: shade(color, 0.5), outlineWidth: 2.5, maxLines: 1)
        }
        .padding(.horizontal, 14)
        .frame(minWidth: height * 1.6, maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background {
            ZStack {
                shape.fill(LinearGradient(colors: [lighten(color, 0.12), color], startPoint: .top, endPoint: .bottom))
                Shine()
            }
        }
        .offset(y: pressed ? pressDepth : 0)
        .animation(pressAnimation(pressed), value: pressed)
        .padding(.bottom, lip)
        .background(alignment: .bottom) {
            shape.fill(shade(color, 0.68)).frame(height: height)
        }
        .contentShape(Rectangle())
    }
}

/// Circular 3D button with white rim, lip and a centred white icon.
struct IconButton3D: View {
    let icon: ImageVector
    let onClick: () -> Void
    /// nil = `LocalPalette.current.accent2`.
    var color: Color? = nil
    var size: CGFloat = 56
    var contentDescription: String? = nil

    @Environment(\.palette) private var p

    init(_ icon: ImageVector, onClick: @escaping () -> Void, color: Color? = nil, size: CGFloat = 56, contentDescription: String? = nil) {
        self.icon = icon
        self.onClick = onClick
        self.color = color
        self.size = size
        self.contentDescription = contentDescription
    }

    var body: some View {
        let onClick = self.onClick
        Button {
            if TapGuard.accept() {
                AudioManager.shared.play(.CLICK)
                Haptics.shared.light()
                onClick()
            }
        } label: {
            EmptyView()
        }
        .buttonStyle(IconButton3DStyle(icon: icon, color: color ?? p.accent2, size: size))
        .accessibilityLabel(contentDescription ?? "")
    }
}

private struct IconButton3DStyle: ButtonStyle {
    let icon: ImageVector
    let color: Color
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let lip: CGFloat = 5
        let pressDepth: CGFloat = 4
        let pressed = configuration.isPressed
        return ZStack(alignment: .top) {
            Circle()
                .fill(shade(color, 0.6))
                .frame(width: size, height: size)
                .offset(y: lip)
            ZStack {
                Circle().fill(Color.white)
                ZStack {
                    Circle().fill(LinearGradient(colors: [lighten(color, 0.14), color], startPoint: .top, endPoint: .bottom))
                    Canvas { ctx, s in
                        let r = CGRect(x: s.width * 0.2, y: s.height * 0.08, width: s.width * 0.6, height: s.height * 0.3)
                        ctx.fill(Path(ellipseIn: r), with: RGBA.white.shading(alpha: 0.32))
                    }
                    Icon(icon, contentDescription: nil, tint: .white)
                        .frame(width: size * 0.48, height: size * 0.48)
                }
                .padding(3)
            }
            .frame(width: size, height: size)
            .offset(y: pressed ? pressDepth : 0)
            .animation(pressAnimation(pressed), value: pressed)
        }
        .frame(width: size, height: size + lip, alignment: .top)
        .contentShape(Rectangle())
    }
}

/// Translucent pill with an icon overlapping its left edge. Clicks (if any) play no sound, like Android.
struct GlassChip<Leading: View>: View {
    let text: String
    var onClick: (() -> Void)? = nil
    var fontSize: CGFloat = 18
    let leading: Leading?

    @Environment(\.palette) private var p

    init(_ text: String, onClick: (() -> Void)? = nil, fontSize: CGFloat = 18, @ViewBuilder leading: () -> Leading) {
        self.text = text
        self.onClick = onClick
        self.fontSize = fontSize
        self.leading = leading()
    }

    var body: some View {
        let hasLeading = leading != nil
        let chip = ZStack(alignment: .leading) {
            OutlinedText(text, fontSize: fontSize, outlineWidth: 2, maxLines: 1)
                .padding(.leading, hasLeading ? 28 : 16)
                .padding(.trailing, 16)
                .frame(height: 36)
                .background(Capsule(style: .circular).fill(p.chipBg))
                .overlay(Capsule(style: .circular).strokeBorder(srgbColor(RGBA(1, 1, 1, 0.3)), lineWidth: 1))
                .clipShape(Capsule(style: .circular))
                .padding(.leading, hasLeading ? 20 : 0)
            if let leading {
                leading.frame(width: 44, height: 44)
            }
        }
        .frame(height: 44)
        if let onClick {
            chip
                .contentShape(Rectangle())
                .onTapGesture { if TapGuard.accept() { onClick() } }
                .accessibilityAddTraits(.isButton)
        } else {
            chip
        }
    }
}

extension GlassChip where Leading == EmptyView {
    init(_ text: String, onClick: (() -> Void)? = nil, fontSize: CGFloat = 18) {
        self.text = text
        self.onClick = onClick
        self.fontSize = fontSize
        self.leading = nil
    }
}

/// Dialog title ribbon: a button-style face with swallow-tail ends behind it.
struct RibbonHeader: View {
    let title: String
    let color: Color
    var width: CGFloat = 250
    var fontSize: CGFloat = 30

    init(_ title: String, _ color: Color, width: CGFloat = 250, fontSize: CGFloat = 30) {
        self.title = title
        self.color = color
        self.width = width
        self.fontSize = fontSize
    }

    var body: some View {
        let tail = shade(color, 0.72)
        let fold = shade(color, 0.5)
        let shape = RoundedRectangle(cornerRadius: 18, style: .circular)
        ZStack(alignment: .top) {
            Canvas { ctx, size in
                let tw: CGFloat = 48
                let top: CGFloat = 16
                let bottom = size.height - 2
                let notch: CGFloat = 14
                let bodyBottom: CGFloat = 62
                func tailPath(_ left: Bool) -> Path {
                    var p = Path()
                    let x0: CGFloat = left ? 0 : size.width
                    let x1: CGFloat = left ? tw : size.width - tw
                    p.move(to: CGPoint(x: x0, y: top))
                    p.addLine(to: CGPoint(x: x1, y: top))
                    p.addLine(to: CGPoint(x: x1, y: bottom))
                    p.addLine(to: CGPoint(x: x0, y: bottom))
                    p.addLine(to: CGPoint(x: x0 + (left ? notch : -notch), y: (top + bottom) / 2))
                    p.closeSubpath()
                    return p
                }
                ctx.fill(tailPath(true), with: .color(tail))
                ctx.fill(tailPath(false), with: .color(tail))
                // Folds where the tails tuck behind the body.
                var f1 = Path()
                f1.move(to: CGPoint(x: 24, y: bodyBottom))
                f1.addLine(to: CGPoint(x: tw, y: bodyBottom))
                f1.addLine(to: CGPoint(x: tw, y: bottom))
                f1.closeSubpath()
                ctx.fill(f1, with: .color(fold))
                var f2 = Path()
                f2.move(to: CGPoint(x: size.width - 24, y: bodyBottom))
                f2.addLine(to: CGPoint(x: size.width - tw, y: bodyBottom))
                f2.addLine(to: CGPoint(x: size.width - tw, y: bottom))
                f2.closeSubpath()
                ctx.fill(f2, with: .color(fold))
            }
            shape.fill(shade(color, 0.68))
                .frame(width: width, height: 56)
                .padding(.top, 6)
            ZStack {
                shape.fill(LinearGradient(colors: [lighten(color, 0.14), color], startPoint: .top, endPoint: .bottom))
                Shine()
                OutlinedText(title, fontSize: fontSize, outline: shade(color, 0.5), outlineWidth: 2.5, maxLines: 1)
            }
            .frame(width: width, height: 56)
        }
        .frame(width: width + 48, height: 76)
    }
}

/// 64×34 pill switch with a springy white knob.
struct ToggleSwitch: View {
    let checked: Bool
    let onCheckedChange: (Bool) -> Void

    @Environment(\.palette) private var p

    init(_ checked: Bool, onCheckedChange: @escaping (Bool) -> Void) {
        self.checked = checked
        self.onCheckedChange = onCheckedChange
    }

    var body: some View {
        let checked = self.checked
        let onCheckedChange = self.onCheckedChange
        ZStack(alignment: .leading) {
            Capsule(style: .circular)
                .fill(checked ? p.success : p.toggleOff)
                .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.2), value: checked)
            Circle()
                .fill(Color.white)
                .frame(width: 28, height: 28)
                .shadow(color: srgbColor(RGBA(0, 0, 0, 0.22)), radius: 1.5, x: 0, y: 1.5)
                .offset(x: checked ? 30 : 0)
                .animation(.compose(dampingRatio: 0.55, stiffness: 500), value: checked)
                .padding(3)
        }
        .frame(width: 64, height: 34)
        .clipShape(Capsule(style: .circular))
        .contentShape(Capsule(style: .circular))
        .onTapGesture {
            if TapGuard.accept() {
                AudioManager.shared.play(.CLICK)
                Haptics.shared.light()
                onCheckedChange(!checked)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(checked ? "On" : "Off")
    }
}

struct SegmentOption {
    let icon: ImageVector
    let label: String

    init(_ icon: ImageVector, _ label: String) {
        self.icon = icon
        self.label = label
    }
}

/// Three-way selector; the selected pill is accent pink with white text. Fills the offered width.
struct Segmented: View {
    let options: [SegmentOption]
    let selected: Int
    let onSelect: (Int) -> Void

    @Environment(\.palette) private var p

    init(_ options: [SegmentOption], selected: Int, onSelect: @escaping (Int) -> Void) {
        self.options = options
        self.selected = selected
        self.onSelect = onSelect
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let sel = i == selected
                let fg = sel ? Color.white : p.subText
                HStack(spacing: 0) {
                    Icon(options[i].icon, contentDescription: nil, tint: fg)
                        .frame(width: 18, height: 18)
                    Spacer().frame(width: 5)
                    BodyText(options[i].label, color: fg, fontSize: TypeScale.Label)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule(style: .circular)
                        .fill(sel ? p.accent : Color(argb: 0x00000000))
                        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.2), value: sel)
                )
                .contentShape(Capsule(style: .circular))
                .onTapGesture {
                    if !sel && TapGuard.accept() {
                        AudioManager.shared.play(.CLICK)
                        onSelect(i)
                    }
                }
                .accessibilityAddTraits(sel ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(Capsule(style: .circular).fill(p.panelAlt))
        .overlay(Capsule(style: .circular).strokeBorder(p.cardBorder, lineWidth: 2))
        .clipShape(Capsule(style: .circular))
    }
}

/// Coloured glossy rounded tile holding a white icon (settings rows, pause rows).
struct IconTile: View {
    let icon: ImageVector
    let color: Color
    var size: CGFloat = 40

    init(_ icon: ImageVector, _ color: Color, size: CGFloat = 40) {
        self.icon = icon
        self.color = color
        self.size = size
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .circular)
        ZStack {
            shape.fill(LinearGradient(colors: [lighten(color, 0.16), color], startPoint: .top, endPoint: .bottom))
            Canvas { ctx, s in
                let r = CGRect(x: s.width * 0.14, y: s.height * 0.1, width: s.width * 0.72, height: s.height * 0.3)
                ctx.fill(Path(roundedRect: r, cornerRadius: min(s.height * 0.15, r.height / 2), style: .circular), with: RGBA.white.shading(alpha: 0.3))
            }
            Icon(icon, contentDescription: nil, tint: .white)
                .frame(width: size * 0.55, height: size * 0.55)
            shape.strokeBorder(shade(color, 0.78), lineWidth: 2)
        }
        .frame(width: size, height: size)
    }
}

// ---------------------------------------------------------------- dialog shell

/**
 * Full-screen dim with a centred CandyCard that scales in (0.6 → 1, springy) and out (→ 0.75).
 * Optional ribbon title straddling the top edge and a red 3D close button.
 * iOS: the dim is a real blur (ultra-thin material) under the palette overlay colour; place the dialog in a
 * full-screen ZStack above the screen (it ignores safe areas for the dim). Taps on the dim are swallowed.
 * Trailing closures: `SweetDialog(…) { content } behind: { … } front: { … }`.
 */
struct SweetDialog<Content: View, Behind: View, Front: View>: View {
    let visible: Bool
    let onDismissRequest: () -> Void
    var title: String? = nil
    /// nil = `LocalPalette.current.accent`.
    var ribbonColor: Color? = nil
    var showClose: Bool = false
    /// nil = `onDismissRequest`.
    var onClose: (() -> Void)? = nil
    let content: Content
    let behind: Behind
    let front: Front

    @Environment(\.palette) private var p

    init(
        _ visible: Bool, onDismissRequest: @escaping () -> Void, title: String? = nil, ribbonColor: Color? = nil,
        showClose: Bool = false, onClose: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content, @ViewBuilder behind: () -> Behind, @ViewBuilder front: () -> Front
    ) {
        self.visible = visible
        self.onDismissRequest = onDismissRequest
        self.title = title
        self.ribbonColor = ribbonColor
        self.showClose = showClose
        self.onClose = onClose
        self.content = content()
        self.behind = behind()
        self.front = front()
    }

    var body: some View {
        ZStack {
            if visible {
                ZStack {
                    ZStack {
                        Rectangle().fill(.ultraThinMaterial)
                        p.overlay
                    }
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    behind
                }
                .transition(.asymmetric(
                    insertion: .opacity.animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.2)),
                    removal: .opacity.animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.18))
                ))
                .zIndex(0)
            }
            if visible {
                card
                    .transition(.asymmetric(
                        insertion: AnyTransition.scale(scale: 0.6).animation(.compose(dampingRatio: 0.55, stiffness: 380))
                            .combined(with: .opacity.animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.2))),
                        removal: AnyTransition.scale(scale: 0.75).combined(with: .opacity)
                            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.18))
                    ))
                    .zIndex(1)
            }
            if visible {
                front
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.2)),
                        removal: .opacity.animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.18))
                    ))
                    .zIndex(2)
            }
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.2), value: visible)
    }

    private var card: some View {
        ZStack(alignment: .top) {
            CandyCard(contentPadding: PaddingValues(start: 18, top: title != nil ? 46 : 22, end: 18, bottom: 20)) {
                content
            }
            .padding(.top, title != nil ? 30 : 0)
            if let title {
                RibbonHeader(title, ribbonColor ?? p.accent)
            }
            if showClose {
                IconButton3D(Icons.Close, onClick: onClose ?? onDismissRequest, color: p.danger, size: 44, contentDescription: "Close")
                    .offset(x: 6, y: 22)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
            }
        }
        .frame(maxWidth: 380)
        .padding(.horizontal, 24)
    }
}

extension SweetDialog where Behind == EmptyView, Front == EmptyView {
    init(
        _ visible: Bool, onDismissRequest: @escaping () -> Void, title: String? = nil, ribbonColor: Color? = nil,
        showClose: Bool = false, onClose: (() -> Void)? = nil, @ViewBuilder content: () -> Content
    ) {
        self.init(visible, onDismissRequest: onDismissRequest, title: title, ribbonColor: ribbonColor, showClose: showClose,
                  onClose: onClose, content: content, behind: { EmptyView() }, front: { EmptyView() })
    }
}

extension SweetDialog where Behind == EmptyView {
    init(
        _ visible: Bool, onDismissRequest: @escaping () -> Void, title: String? = nil, ribbonColor: Color? = nil,
        showClose: Bool = false, onClose: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content, @ViewBuilder front: () -> Front
    ) {
        self.init(visible, onDismissRequest: onDismissRequest, title: title, ribbonColor: ribbonColor, showClose: showClose,
                  onClose: onClose, content: content, behind: { EmptyView() }, front: front)
    }
}

extension SweetDialog where Front == EmptyView {
    init(
        _ visible: Bool, onDismissRequest: @escaping () -> Void, title: String? = nil, ribbonColor: Color? = nil,
        showClose: Bool = false, onClose: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content, @ViewBuilder behind: () -> Behind
    ) {
        self.init(visible, onDismissRequest: onDismissRequest, title: title, ribbonColor: ribbonColor, showClose: showClose,
                  onClose: onClose, content: content, behind: behind, front: { EmptyView() })
    }
}
