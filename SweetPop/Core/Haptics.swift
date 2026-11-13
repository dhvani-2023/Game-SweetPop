import UIKit
import GameKit

/// Light / medium / heavy haptic taps (Kotlin `core/Haptics`).
///
/// Android plays the predefined effects TICK / CLICK / HEAVY_CLICK (API 29+), falling back to one-shots of
/// 12 ms @ 70, 22 ms @ 150 and 40 ms @ 255. On iPhone the closest Taptic Engine equivalents are the impact
/// generators (light / medium / heavy) at matching strengths. App-wide instance: `Haptics.shared`
/// (Kotlin `LocalHaptics.current` / `container.haptics`).
@MainActor
final class Haptics {
    static let shared = Haptics()

    /// Vibration setting (Kotlin `@Volatile var enabled`).
    var enabled: Bool = true

    private init() {
        GameKit.Haptics.prepare()
    }

    func light() { buzz(.LIGHT) }
    func medium() { buzz(.MEDIUM) }
    func heavy() { buzz(.HEAVY) }

    /// Plays even when disabled; used for the settings test buzz right after enabling.
    func test() { buzz(.MEDIUM, force: true) }

    private enum Strength {
        case LIGHT // 12 ms, amplitude 70, EFFECT_TICK
        case MEDIUM // 22 ms, amplitude 150, EFFECT_CLICK
        case HEAVY // 40 ms, amplitude 255, EFFECT_HEAVY_CLICK

        var ms: Int {
            switch self {
            case .LIGHT: return 12
            case .MEDIUM: return 22
            case .HEAVY: return 40
            }
        }

        var amplitude: Int {
            switch self {
            case .LIGHT: return 70
            case .MEDIUM: return 150
            case .HEAVY: return 255
            }
        }
    }

    private func buzz(_ s: Strength, force: Bool = false) {
        // This class is the gate (GameKit's global `Haptics.enabled` is left on so `test()` can force a buzz).
        if !enabled && !force { return }
        switch s {
        case .LIGHT: GameKit.Haptics.tap(0.7) // crisp tick
        case .MEDIUM: GameKit.Haptics.medium(0.85) // click
        case .HEAVY: GameKit.Haptics.heavy(1.0) // heavy click
        }
    }
}
