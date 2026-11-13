import SwiftUI
import GameKit

private struct DocSection {
    let heading: String
    let body: String
}

private struct Doc {
    let title: String
    let updated: String
    let sections: [DocSection]
}

private let STUDIO = "NG Studio (NGENDEV TECHNOLABS LLP)"
private let SUPPORT_EMAIL = "ngendevtech@gmail.com"
private let UPDATED = "Last updated: 8 November 2026"

private let TERMS = Doc(
    title: "Terms & Conditions",
    updated: UPDATED,
    sections: [
        DocSection(heading: "1. Acceptance", body: "By downloading or playing Sweet Pop you agree to these Terms. If you do not agree, please uninstall the game."),
        DocSection(heading: "2. Licence", body: "We grant you a personal, non-exclusive, non-transferable, revocable licence to play Sweet Pop for personal, non-commercial use."),
        DocSection(heading: "3. Restrictions", body: "You may not copy, modify, reverse engineer, redistribute or sell the game or any part of it, except where the law permits."),
        DocSection(heading: "4. Offline play & progress", body: "Sweet Pop plays fully offline. Your progress is stored only on your device; uninstalling the game or clearing its data deletes it permanently."),
        DocSection(heading: "5. Virtual items", body: "Lives, stars and scores are part of the game only and have no monetary value."),
        DocSection(heading: "6. Updates", body: "Updates may add content or change features."),
        DocSection(heading: "7. Disclaimer", body: "The game is provided \"as is\" without warranties of any kind. Where permitted by law, we are not liable for any indirect loss arising from its use."),
        DocSection(heading: "8. Changes to these Terms", body: "We may update these Terms from time to time. Continued use of the game means you accept the updated Terms."),
        DocSection(heading: "9. Contact", body: "\(STUDIO)\n\(SUPPORT_EMAIL)"),
    ]
)

private let PRIVACY = Doc(
    title: "Privacy Policy",
    updated: UPDATED,
    sections: [
        DocSection(heading: "Summary", body: "Sweet Pop is an offline game. There is no account, and no personal data is collected, stored or shared."),
        DocSection(heading: "Data on your device", body: "Your level progress, stars, best scores, lives and settings are stored locally on your device and are deleted when you uninstall the game."),
        DocSection(heading: "Permissions", body: "Vibration, used for haptic feedback. You can turn it off in Settings."),
        DocSection(heading: "Children", body: "We do not collect personal information from anyone, including children."),
        DocSection(heading: "Third-party services", body: "None in this version: no ads, analytics or tracking. This policy will be updated if that changes."),
        DocSection(heading: "Contact", body: SUPPORT_EMAIL),
    ]
)

/// Terms & Conditions or Privacy Policy, rendered from the text above inside a scrolling candy card.
struct DocumentScreen: View {
    let kind: String
    let onBack: () -> Void

    @Environment(\.palette) private var p
    @Environment(\.safeDrawingInsets) private var safe
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ kind: String, onBack: @escaping () -> Void) {
        self.kind = kind
        self.onBack = onBack
    }

    var body: some View {
        let doc = kind == "privacy" ? PRIVACY : TERMS
        // TextStyle(Fredoka, 20 sp) headings; 16 sp body with lineHeight 23 sp.
        let bodySpacing = fredokaLineSpacing(fontSize: 16, lineHeight: 23, dynamicType: dynamicTypeSize)
        VStack(spacing: 0) {
            ScreenHeader(title: kind == "privacy" ? "Privacy" : "Terms", onBack: onBack)
            CandyCard(contentPadding: PaddingValues(0), horizontalAlignment: .leading) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(doc.title)
                            .font(.fredoka(26))
                            .foregroundStyle(p.accent)
                        Color.clear.frame(height: 4)
                        Text(doc.updated)
                            .font(.fredoka(16))
                            .foregroundStyle(p.subText)
                            .lineSpacing(bodySpacing)
                        ForEach(doc.sections.indices, id: \.self) { i in
                            let s = doc.sections[i]
                            Color.clear.frame(height: 16)
                            Text(s.heading)
                                .font(.fredoka(20))
                                .foregroundStyle(p.text)
                            Color.clear.frame(height: 4)
                            Text(s.body)
                                .font(.fredoka(16))
                                .foregroundStyle(p.text)
                                .lineSpacing(bodySpacing)
                        }
                        Color.clear.frame(height: 12)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
            }
            .padding(EdgeInsets(top: 6, leading: 16, bottom: 16, trailing: 16))
        }
        .padding(safe)
        .ignoresSafeArea()
    }
}
