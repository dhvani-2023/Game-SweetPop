import Foundation
import UIKit
import GameKit

/**
 * Effects through GameKit `SoundBank` (12 voices, like Android's 12 SoundPool streams) and looping music through
 * GameKit `MusicPlayer` with crossfades and ducking (Kotlin `AudioManager`: SoundPool + MediaPlayer).
 * A bundled file named like an effect or track (e.g. `pop.caf`, `music_menu.m4a`) replaces the synthesised one.
 *
 * App-wide instance: `AudioManager.shared` (Kotlin `container.audio` / `LocalAudio.current`).
 * Launch order (splash): `await SynthBank.ensureGenerated { … }` → `loadAll()` → `playMusic(.MENU)`.
 * Background/foreground pausing is automatic (`onStop()` / `onStart()` are also public, as on Android).
 */
@MainActor
final class AudioManager {
    static let shared = AudioManager()

    static let BASE_MUSIC_VOLUME: Float = 0.42
    /// Ducked music level: BASE × 0.35 (Kotlin `musicVolume` while ducked).
    private static let DUCK_FACTOR: Float = 0.35
    /// Android crossfade (30 steps over 750 ms) and duck ramp (12 steps over 300 ms).
    private static let CROSSFADE_SECONDS: Double = 0.75
    private static let DUCK_SECONDS: Double = 0.3

    private let soundBank = SoundBank(voices: 12)
    private let music = MusicPlayer()

    private var loaded = false

    /// Sound effects setting (Kotlin `@Volatile var sfxEnabled`).
    var sfxEnabled: Bool = true

    private var musicEnabled = true
    private var desired: Music?
    private var currentTrack: Music?
    private var ducked = false
    private var foreground = true
    private var observers: [NSObjectProtocol] = []

    private init() {
        music.volume = AudioManager.BASE_MUSIC_VOLUME // linear gain, like Android MediaPlayer.setVolume
        AudioSystem.shared.start()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AudioManager.shared.onStop() }
        })
        observers.append(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AudioManager.shared.onStart() }
        })
    }

    /// Registers every effect, chime and music track. Call after `SynthBank.ensureGenerated`.
    func loadAll() {
        if loaded { return }
        loaded = true
        let names = Sfx.allCases.map(\.fileName) + SynthBank.CHIME_STEPS.indices.map { SynthBank.chimeName($0) }
        for name in names {
            let gap: TimeInterval = name == Sfx.LAND.fileName ? 0.05 : 0 // Kotlin: LAND at most every 50 ms
            if soundBank.load(name, minGap: gap) { continue }
            if let pcm = SynthBank.samples(name) { soundBank.register(name, samples: pcm, minGap: gap) }
        }
        for m in Music.allCases {
            if music.load(m.fileName) { continue }
            if let pcm = SynthBank.samples(m.fileName) { music.register(m.fileName, samples: pcm) }
        }
        SynthBank.releaseMemory()
        // The desired track may have been requested before the sounds existed.
        if let d = desired {
            currentTrack = nil
            playMusic(d)
        }
    }

    func play(_ sfx: Sfx, rate: Float = 1, volume: Float = 1) {
        if !sfxEnabled { return }
        playNamed(sfx.fileName, rate, volume)
    }

    /// Chime pitched up one pentatonic step per cascade level.
    func playChime(_ cascade: Int, volume: Float = 0.8) {
        if !sfxEnabled { return }
        playNamed(SynthBank.chimeName(cascade.coerceIn(0, SynthBank.CHIME_STEPS.count - 1)), 1, volume)
    }

    private func playNamed(_ name: String, _ rate: Float, _ volume: Float) {
        soundBank.play(name, volume: volume.coerceIn(0, 1), rate: rate.coerceIn(0.5, 2))
    }

    // ------------------------------------------------------------------ music

    func setMusicEnabled(_ on: Bool) {
        if musicEnabled == on { return }
        musicEnabled = on
        if on {
            if let d = desired {
                currentTrack = nil
                playMusic(d)
            }
        } else {
            fadeTo(nil)
        }
    }

    func playMusic(_ track: Music) {
        desired = track
        if !musicEnabled || !foreground || !loaded { return }
        if currentTrack == track { return }
        fadeTo(track)
    }

    func duck(_ on: Bool) {
        if ducked == on { return }
        ducked = on
        // Android ramps 0.42 → 0.42 × 0.35 (and back) linearly over 300 ms.
        music.setDuck(on ? Self.DUCK_FACTOR : 1, fade: Self.DUCK_SECONDS)
    }

    /// App came to the foreground (Kotlin Activity.onStart).
    func onStart() {
        if foreground { return }
        foreground = true
        AudioSystem.shared.resume()
        if let d = desired, musicEnabled, currentTrack != d {
            playMusic(d)
        }
    }

    /// App went to the background (Kotlin Activity.onStop): everything pauses.
    func onStop() {
        if !foreground { return }
        foreground = false
        AudioSystem.shared.suspend()
    }

    private func fadeTo(_ track: Music?) {
        guard let track else {
            currentTrack = nil
            music.play(nil, fade: Self.CROSSFADE_SECONDS)
            return
        }
        guard music.has(track.fileName) else {
            currentTrack = nil
            music.play(nil, fade: Self.CROSSFADE_SECONDS)
            return
        }
        currentTrack = track
        // Android: 750 ms linear crossfade.
        music.play(track.fileName, fade: Self.CROSSFADE_SECONDS)
    }
}
