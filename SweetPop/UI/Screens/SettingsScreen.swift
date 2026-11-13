import SwiftUI
import GameKit

/// Sound, appearance, gameplay and about sections, plus Reset Progress (with a "Fresh Start!" praise word).
struct SettingsScreen: View {
    let onBack: () -> Void
    let onReplayTutorial: () -> Void
    let onDocument: (String) -> Void
    let onDebug: () -> Void

    @Environment(\.palette) private var p
    @Environment(AppContainer.self) private var container
    @Environment(\.safeDrawingInsets) private var safe

    @State private var confirmReset = false
    @State private var freshStart = 0

    var body: some View {
        let save = container.save.state
        let repo = container.save
        let haptics = container.haptics
        ZStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Settings", onBack: onBack)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSection("SOUND") {
                            ToggleRow(Icons.Music, p.accent, "Music", save.music) { repo.setMusic($0) }
                            RowDivider()
                            ToggleRow(Icons.Sound, p.accent2, "Sound Effects", save.sfx) { repo.setSfx($0) }
                            RowDivider()
                            ToggleRow(Icons.Vibration, p.sky, "Vibration", save.vibration) { on in
                                repo.setVibration(on)
                                if on { haptics.test() }
                            }
                        }
                        SettingsSection("APPEARANCE") {
                            HStack(spacing: 0) {
                                IconTile(Icons.Sun, p.gold)
                                Color.clear.frame(width: 14, height: 1)
                                BodyText("Theme", color: p.text, textAlign: .leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            Segmented(
                                [SegmentOption(Icons.Sun, "Light"), SegmentOption(Icons.Moon, "Dark"), SegmentOption(Icons.Auto, "Auto")],
                                selected: save.theme,
                                onSelect: { repo.setTheme($0) }
                            )
                            .padding(.bottom, 6)
                        }
                        SettingsSection("GAMEPLAY") {
                            ToggleRow(Icons.Bulb, p.gold, "Show Hints", save.hints) { repo.setHints($0) }
                            RowDivider()
                            if Features.colorBlind {
                                // iOS extras: a symbol on every candy (Extras/UI/ColorBlindSymbols.swift).
                                ToggleRow(ExtrasIcons.Eye, p.sky, "Colour-blind symbols", repo.extras.colorBlind) { repo.setColorBlind($0) }
                                RowDivider()
                            }
                            LinkRow(Icons.Replay, p.mint, "Replay Tutorial", onClick: onReplayTutorial)
                        }
                        SettingsSection("ABOUT") {
                            LinkRow(Icons.Document, p.sky, "Terms & Conditions") { onDocument("terms") }
                            RowDivider()
                            LinkRow(Icons.Shield, p.mint, "Privacy Policy") { onDocument("privacy") }
                            RowDivider()
                            // Android opens the Play Store page; iOS asks StoreKit for the rating prompt.
                            LinkRow(Icons.Star, p.gold, "Rate Sweet Pop") { AppLinks.requestReview() }
                            #if DEBUG
                            RowDivider()
                            LinkRow(Icons.Music, p.accent2, "Sound & Candy Board (debug)", onClick: onDebug)
                            #endif
                        }
                        Color.clear.frame(height: 14)
                        CandyCard(contentPadding: PaddingValues(horizontal: 14, vertical: 6)) {
                            LinkRow(Icons.Trash, p.danger, "Reset Progress", labelColor: p.danger) { confirmReset = true }
                        }
                        Color.clear.frame(height: 18)
                        // Compose wraps OutlinedText in a Box, so with fillMaxWidth the line sits at the start.
                        OutlinedText("Sweet Pop v\(Platform.versionName) — Plays fully offline", fontSize: TypeScale.Caption, outlineWidth: 1.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 18)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
            .padding(safe)

            FreshStartWord(trigger: freshStart)

            ConfirmDialog(
                visible: confirmReset,
                title: "Reset?",
                message: Features.economy
                    ? "This clears all levels, stars, scores, coins and boosters. Your settings stay."
                    : "This clears all levels, stars and scores. Your settings stay.",
                yes: "Reset",
                no: "Cancel",
                destructive: true,
                onYes: {
                    repo.resetProgress()
                    // iOS extras: coins, boosters, chests and a saved level start over too.
                    if Features.economy || Features.boosters || Features.episodeChest {
                        repo.resetExtrasProgress()
                        container.extras.coinsInFlight = 0
                    }
                    if Features.autosave { AutoSave.clear() }
                    confirmReset = false
                    container.audio.play(.WHOOSH)
                    freshStart += 1
                },
                onNo: { confirmReset = false }
            )
        }
        .ignoresSafeArea()
    }
}

/// Pops the "Fresh Start!" praise word after a progress reset (full-screen effects canvas).
private struct FreshStartWord: View {
    let trigger: Int

    @State private var fx = Effects()
    @State private var loop = GameLoop()
    @State private var area: CGSize = .zero

    var body: some View {
        let fx = self.fx
        let loop = self.loop
        GeometryReader { g in
            let frameTick = loop.frame
            Canvas { ctx, _ in _ = frameTick; fx.draw(ctx) }
                .onAppear { area = g.size }
                .onChange(of: g.size) { _, s in area = s }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, t in
            if t == 0 { return }
            fx.praise("Fresh Start!", Float(area.width / 2), Float(area.height * 0.45))
            Self.run(fx, loop)
        }
        .onDisappear { loop.stop() }
    }

    /// Kotlin: `while (fx.isBusy) withFrameNanos { fx.update(dt ≤ 0.05 s) }`, then one last redraw.
    private static func run(_ fx: Effects, _ loop: GameLoop) {
        loop.maxDelta = 0.05
        loop.onTick = { [weak loop] dt in
            fx.update(Float(dt))
            if !fx.isBusy { loop?.stop() }
        }
        loop.start()
    }
}

private struct SettingsSection<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        Color.clear.frame(height: 10)
        OutlinedText(label, fontSize: TypeScale.Label, outlineWidth: 2)
            .padding(.leading, 8)
            .padding(.bottom, 6)
        CandyCard(contentPadding: PaddingValues(horizontal: 14, vertical: 6), horizontalAlignment: .leading) {
            content
        }
    }
}

private struct RowDivider: View {
    @Environment(\.palette) private var p

    var body: some View {
        Rectangle().fill(p.divider).frame(maxWidth: .infinity).frame(height: 1.5)
    }
}

private struct LinkRow: View {
    let icon: ImageVector
    let color: Color
    let label: String
    var labelColor: Color? = nil
    let onClick: () -> Void

    @Environment(\.palette) private var p
    @Environment(AppContainer.self) private var container

    init(_ icon: ImageVector, _ color: Color, _ label: String, labelColor: Color? = nil, onClick: @escaping () -> Void) {
        self.icon = icon
        self.color = color
        self.label = label
        self.labelColor = labelColor
        self.onClick = onClick
    }

    var body: some View {
        let audio = container.audio
        let onClick = self.onClick
        HStack(spacing: 0) {
            IconTile(icon, color)
            Color.clear.frame(width: 14, height: 1)
            BodyText(label, color: labelColor ?? p.text, textAlign: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Icon(Icons.Next, contentDescription: nil, tint: p.subText)
                .frame(width: 26, height: 26)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if TapGuard.accept() {
                audio.play(.CLICK)
                onClick()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
