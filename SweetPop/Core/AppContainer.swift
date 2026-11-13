import SwiftUI
import Observation
import GameKit

/// App-wide singletons: save data, audio and haptics (Kotlin `core/AppContainer`).
///
/// Created once by `SweetPopApp` and injected with `.environment(container)`; views read it with
/// `@Environment(AppContainer.self) private var container` (Kotlin `LocalAppContainer.current`).
/// `audio` and `haptics` are the same instances the design components use (`AudioManager.shared`,
/// `Haptics.shared`, i.e. Kotlin `LocalAudio` / `LocalHaptics`).
@MainActor
@Observable
final class AppContainer {
    let save: SaveRepository
    let haptics: Haptics
    let audio: AudioManager

    /// Set when the player leaves a won level for the map, so Home can play the pin-hop.
    /// A plain property like Kotlin's `var` (not observed: Home reads and clears it once when it appears).
    @ObservationIgnored var pendingPinHopFrom: Int? = nil

    /// iOS extras session state: coins waiting to fly into the map's coin pill, a level to restore
    /// (Extras/ExtrasState.swift; features switched in Extras/Features.swift).
    let extras = ExtrasSession()

    init(save: SaveRepository = SaveRepository()) {
        self.save = save
        self.haptics = Haptics.shared
        self.audio = AudioManager.shared // starts the audio engine
        syncSettings()
    }

    /// Kotlin `init { scope.launch { save.state.collect { … } } }`: every saved-state change re-applies the
    /// sound, music and vibration settings.
    private func syncSettings() {
        withObservationTracking {
            let s = save.state
            if s.loaded {
                audio.sfxEnabled = s.sfx
                audio.setMusicEnabled(s.music)
                haptics.enabled = s.vibration
            }
        } onChange: { [weak self] in
            // Called before the change is applied: re-read on the main actor once it has landed.
            Task { @MainActor in self?.syncSettings() }
        }
    }
}
