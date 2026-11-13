import Foundation
import Observation
import GameKit

let LEVEL_COUNT = 2000

/// Everything the game persists on the device.
struct SaveData {
    let loaded: Bool
    let highestUnlocked: Int
    let stars: [Int]
    let bestScores: [Int]
    let lives: Int
    let nextLifeAtMillis: Int64
    let music: Bool
    let sfx: Bool
    let vibration: Bool
    let hints: Bool
    let theme: Int
    let onboardingDone: Bool
    let termsAccepted: Bool
    let lastPlayedLevel: Int
    /// Kotlin `by lazy { stars.sum() }`, computed once here.
    let totalStars: Int

    init(
        loaded: Bool = false,
        highestUnlocked: Int = 1,
        stars: [Int] = [Int](repeating: 0, count: LEVEL_COUNT),
        bestScores: [Int] = [Int](repeating: 0, count: LEVEL_COUNT),
        lives: Int = Lives.MAX,
        nextLifeAtMillis: Int64 = 0,
        music: Bool = true,
        sfx: Bool = true,
        vibration: Bool = true,
        hints: Bool = true,
        theme: Int = 0,
        onboardingDone: Bool = false,
        termsAccepted: Bool = false,
        lastPlayedLevel: Int = 1
    ) {
        self.loaded = loaded
        self.highestUnlocked = highestUnlocked
        self.stars = stars
        self.bestScores = bestScores
        self.lives = lives
        self.nextLifeAtMillis = nextLifeAtMillis
        self.music = music
        self.sfx = sfx
        self.vibration = vibration
        self.hints = hints
        self.theme = theme
        self.onboardingDone = onboardingDone
        self.termsAccepted = termsAccepted
        self.lastPlayedLevel = lastPlayedLevel
        self.totalStars = stars.reduce(0, +)
    }

    func starsFor(_ level: Int) -> Int { level - 1 >= 0 && level - 1 < stars.count ? stars[level - 1] : 0 }
    func bestFor(_ level: Int) -> Int { level - 1 >= 0 && level - 1 < bestScores.count ? bestScores[level - 1] : 0 }
    func livesNow(now: Int64 = Days.nowMillis()) -> Lives.State { Lives.refresh(lives, nextLifeAtMillis, now) }
}

/// UserDefaults-backed save (GameKit `Prefs` named "sweetpop", Android's DataStore keys and encodings):
/// progress, settings and lives. All writes are applied immediately and `state` is re-read after each one.
/// Kotlin's `state.value` is `state` here (observable).
@Observable
final class SaveRepository {
    /// Internal (not private) so the iOS extras keep their keys in the same store (Extras/SaveRepository+Extras.swift).
    @ObservationIgnored let store: Prefs

    private(set) var state: SaveData

    private enum K {
        static let highestUnlocked = "highestUnlocked"
        static let stars = "stars"
        static let bestScores = "bestScores"
        static let lives = "lives"
        static let nextLifeAt = "nextLifeAtMillis"
        static let music = "music"
        static let sfx = "sfx"
        static let vibration = "vibration"
        static let hints = "hints"
        static let theme = "theme"
        static let onboardingDone = "onboardingDone"
        static let termsAccepted = "termsAccepted"
        static let lastPlayedLevel = "lastPlayedLevel"
    }

    init(store: Prefs = Prefs(name: "sweetpop")) {
        self.store = store
        self.state = SaveRepository.parse(store)
    }

    private static func parse(_ p: Prefs) -> SaveData {
        SaveData(
            loaded: true,
            highestUnlocked: p.int(K.highestUnlocked, 1).coerceIn(1, LEVEL_COUNT),
            stars: decodeStars(p.optionalString(K.stars)),
            bestScores: decodeInts(p.optionalString(K.bestScores)),
            lives: p.int(K.lives, Lives.MAX),
            nextLifeAtMillis: p.long(K.nextLifeAt, 0),
            music: p.bool(K.music, true),
            sfx: p.bool(K.sfx, true),
            vibration: p.bool(K.vibration, true),
            hints: p.bool(K.hints, true),
            theme: p.int(K.theme, 0),
            onboardingDone: p.bool(K.onboardingDone, false),
            termsAccepted: p.bool(K.termsAccepted, false),
            lastPlayedLevel: p.int(K.lastPlayedLevel, 1)
        )
    }

    private func edit(_ block: (Prefs) -> Void) {
        block(store)
        state = SaveRepository.parse(store)
    }

    func setMusic(_ on: Bool) { edit { $0.set(K.music, on) } }
    func setSfx(_ on: Bool) { edit { $0.set(K.sfx, on) } }
    func setVibration(_ on: Bool) { edit { $0.set(K.vibration, on) } }
    func setHints(_ on: Bool) { edit { $0.set(K.hints, on) } }
    func setTheme(_ mode: Int) { edit { $0.set(K.theme, mode) } }
    func setLastPlayed(_ level: Int) { edit { $0.set(K.lastPlayedLevel, level) } }

    func completeOnboarding() {
        edit { p in
            p.set(K.onboardingDone, true)
            p.set(K.termsAccepted, true)
        }
    }

    /// Records a win: best stars & score, and unlocks the next level.
    func recordWin(_ level: Int, _ stars: Int, _ score: Int) {
        edit { p in
            var s = SaveRepository.decodeStars(p.optionalString(K.stars))
            var b = SaveRepository.decodeInts(p.optionalString(K.bestScores))
            let i = level - 1
            if i >= 0 && i < LEVEL_COUNT {
                s[i] = max(s[i], stars.coerceIn(0, 3))
                b[i] = max(b[i], score)
            }
            p.set(K.stars, SaveRepository.encodeStars(s))
            p.set(K.bestScores, b.map(String.init).joined(separator: ","))
            let unlocked = p.int(K.highestUnlocked, 1)
            p.set(K.highestUnlocked, max(unlocked, (level + 1).coerceAtMost(LEVEL_COUNT)))
            p.set(K.lastPlayedLevel, level)
        }
    }

    /// Applies regenerated lives (call on start/resume).
    func refreshLives(now: Int64 = Days.nowMillis()) {
        edit { p in
            let s = Lives.refresh(p.int(K.lives, Lives.MAX), p.long(K.nextLifeAt, 0), now)
            p.set(K.lives, s.lives)
            p.set(K.nextLifeAt, s.nextLifeAtMillis)
        }
    }

    func consumeLife(now: Int64 = Days.nowMillis()) {
        edit { p in
            let s = Lives.consume(p.int(K.lives, Lives.MAX), p.long(K.nextLifeAt, 0), now)
            p.set(K.lives, s.lives)
            p.set(K.nextLifeAt, s.nextLifeAtMillis)
        }
    }

    func refundLife(now: Int64 = Days.nowMillis()) {
        edit { p in
            let s = Lives.refund(p.int(K.lives, Lives.MAX), p.long(K.nextLifeAt, 0), now)
            p.set(K.lives, s.lives)
            p.set(K.nextLifeAt, s.nextLifeAtMillis)
        }
    }

    /// Clears progress and lives but keeps settings, onboarding and terms flags.
    func resetProgress() {
        edit { p in
            p.remove(K.highestUnlocked)
            p.remove(K.stars)
            p.remove(K.bestScores)
            p.remove(K.lives)
            p.remove(K.nextLifeAt)
            p.remove(K.lastPlayedLevel)
        }
    }

    // ------------------------------------------------------------------ encodings (same as Android)

    /// One digit '0'…'3' per level; a missing or short string reads as zeros.
    static func decodeStars(_ s: String?) -> [Int] {
        var out = [Int](repeating: 0, count: LEVEL_COUNT)
        guard let s else { return out }
        let units = Array(s.utf16)
        for i in 0..<min(units.count, LEVEL_COUNT) { out[i] = (Int(units[i]) - 48).coerceIn(0, 3) }
        return out
    }

    /// Trailing zeros are dropped to keep the value small.
    static func encodeStars(_ a: [Int]) -> String {
        var last = a.count - 1
        while last >= 0 && a[last] == 0 { last -= 1 }
        var units = [UInt16]()
        units.reserveCapacity(last + 1)
        if last >= 0 {
            for i in 0...last { units.append(UInt16(truncatingIfNeeded: 48 + a[i])) }
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// Comma-joined ints; unparsable entries read as 0 (Kotlin `toIntOrNull() ?: 0`).
    static func decodeInts(_ s: String?) -> [Int] {
        var out = [Int](repeating: 0, count: LEVEL_COUNT)
        guard let s, !s.isEmpty else { return out }
        for (i, v) in s.split(separator: ",", omittingEmptySubsequences: false).enumerated() where i < LEVEL_COUNT {
            out[i] = Int32(v).map { Int($0) } ?? 0
        }
        return out
    }
}
