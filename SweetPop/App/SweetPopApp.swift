import SwiftUI
import UIKit
import Observation
import GameKit

// Port of `SweetPopApp.kt` (theme + navigation + app-wide providers) and `MainActivity.kt` (launch, lifecycle).

@main
struct SweetPopApp: App {
    @State private var container: AppContainer

    init() {
        // Fredoka must be registered before the first text is laid out.
        SweetPopFonts.register()
        // Kotlin SweetPopApplication.onCreate: save data, haptics, audio (starts the audio engine).
        _container = State(initialValue: AppContainer())
    }

    var body: some Scene {
        WindowGroup {
            SweetPopRoot()
                .environment(container)
        }
    }
}

// MARK: - Routes

/// Kotlin `private object Routes` — the route templates double as destination patterns.
enum Routes {
    static let SPLASH = "splash"
    static let ONBOARDING = "onboarding?replay={replay}"
    static let HOME = "home"
    static let GAME = "game/{level}"
    static let SETTINGS = "settings"
    static let DOC = "doc/{kind}"
    static let DEBUG = "debug"
}

/// A destination with its arguments (Kotlin `Routes.onboarding(replay)`, `Routes.game(level)`, `Routes.doc(kind)`).
enum Route: Hashable {
    case splash
    case onboarding(replay: Bool)
    case home
    case game(level: Int)
    case settings
    case doc(kind: String)
    case debug

    /// The destination's route template; `popUpTo` and `launchSingleTop` match on it, like Navigation.
    var pattern: String {
        switch self {
        case .splash: return Routes.SPLASH
        case .onboarding: return Routes.ONBOARDING
        case .home: return Routes.HOME
        case .game: return Routes.GAME
        case .settings: return Routes.SETTINGS
        case .doc: return Routes.DOC
        case .debug: return Routes.DEBUG
        }
    }

    /// Navigation keeps a covered destination's saveable state (`rememberPagerState`, `rememberScrollState`) and
    /// restores it on return. Onboarding (page) and Settings (scroll position) stay alive, hidden, while covered.
    /// Everything else is torn down and recreated on return, like Compose's plain `remember` + `LaunchedEffect`
    /// (Home re-runs its music / lives refresh / auto-scroll each time it is shown).
    var keepsStateWhenCovered: Bool {
        switch self {
        case .onboarding, .settings: return true
        default: return false
        }
    }
}

// MARK: - Router (Kotlin NavHost + NavController)

/**
 * A small back-stack router drawn as a ZStack (no NavigationStack push animations).
 * Transitions match the Android NavHost: the entering destination fades in (300 ms) while scaling from 1.04, the
 * leaving one fades out (300 ms); both use `tween(300)` (FastOutSlowIn). A push draws the new destination on top
 * (z + 1), a pop draws the revealed destination underneath the one fading out (z − 1).
 */
@MainActor
@Observable
final class Router {
    struct Entry: Identifiable, Equatable {
        let id: Int
        let route: Route
        /// NavHost z-index.
        var z: Double
        /// Content is in the view tree (covered destinations are unmounted unless they keep state).
        var mounted: Bool
        /// Covered but kept alive: faded out and inactive.
        var hidden: Bool
        /// 1.04 once hidden, so returning to it scales in like `popEnterTransition`.
        var scale: CGFloat
    }

    /// Back stack, bottom first. Entries leave it as soon as they are popped; SwiftUI keeps their views for the fade.
    private(set) var stack: [Entry]
    @ObservationIgnored private var nextId = 1

    /// Kotlin `tween(300)`: FastOutSlowInEasing.
    static let transition = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.3)

    init(start: Route) {
        stack = [Entry(id: 0, route: start, z: 0, mounted: true, hidden: false, scale: 1)]
    }

    var top: Entry { stack[stack.count - 1] }

    /// Kotlin `currentBackStackEntryAsState()` destination: changes as soon as a navigation starts.
    var current: Route { top.route }

    /// Kotlin `nav.navigate(route) { popUpTo(pattern) { inclusive }; launchSingleTop }`.
    func navigate(_ route: Route, popUpTo pattern: String? = nil, inclusive: Bool = false, launchSingleTop: Bool = false) {
        let from = top
        if launchSingleTop && from.route.pattern == route.pattern { return }
        var next = stack
        if let pattern, let i = next.lastIndex(where: { $0.route.pattern == pattern }) {
            next.removeSubrange((inclusive ? i : i + 1)...)
        }
        if let k = next.firstIndex(where: { $0.id == from.id }) {
            // Still on the back stack: covered.
            if next[k].route.keepsStateWhenCovered { next[k].hidden = true } else { next[k].mounted = false }
        }
        next.append(Entry(id: nextId, route: route, z: from.z + 1, mounted: true, hidden: false, scale: 1))
        nextId += 1
        let covered = from.id
        withAnimation(Self.transition, completionCriteria: .logicallyComplete) {
            stack = next
        } completion: { [weak self] in
            self?.settleHidden(covered)
        }
    }

    /// Kotlin `nav.popBackStack()`. The last destination is never popped.
    @discardableResult
    func popBackStack() -> Bool {
        guard stack.count > 1 else { return false }
        pop(to: stack.count - 2)
        return true
    }

    /// Kotlin `nav.popBackStack(pattern, inclusive)`.
    @discardableResult
    func popBackStack(_ pattern: String, inclusive: Bool) -> Bool {
        guard let i = stack.lastIndex(where: { $0.route.pattern == pattern }) else { return false }
        let target = inclusive ? i - 1 : i
        guard target >= 0, target < stack.count - 1 else { return false }
        pop(to: target)
        return true
    }

    private func pop(to target: Int) {
        let from = top
        var next = Array(stack[...target])
        var to = next[target]
        to.z = from.z - 1
        to.mounted = true // recreated (fresh state) unless it was kept alive
        to.hidden = false
        to.scale = 1
        next[target] = to
        withAnimation(Self.transition) {
            stack = next
        }
    }

    /// Once a kept-alive destination has faded out, pre-scale it (invisibly) for its next pop-enter.
    private func settleHidden(_ id: Int) {
        guard let k = stack.firstIndex(where: { $0.id == id }), stack[k].hidden, stack[k].scale != 1.04 else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { stack[k].scale = 1.04 }
    }
}

/// Enter: fade in + scale from 1.04. Exit: fade out (and stop taking touches right away).
private struct RouteEnterFX: ViewModifier {
    let opacity: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content.opacity(opacity).scaleEffect(scale)
    }
}

private struct RouteExitFX: ViewModifier {
    let leaving: Bool

    func body(content: Content) -> some View {
        content.opacity(leaving ? 0 : 1).allowsHitTesting(!leaving)
    }
}

private extension AnyTransition {
    static var route: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: RouteEnterFX(opacity: 0, scale: 1.04), identity: RouteEnterFX(opacity: 1, scale: 1)),
            removal: .modifier(active: RouteExitFX(leaving: true), identity: RouteExitFX(leaving: false))
        )
    }
}

// MARK: - Environment shared by the shell screens

private struct SafeDrawingInsetsKey: EnvironmentKey {
    static let defaultValue = EdgeInsets()
}

private struct RouteActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Kotlin `WindowInsets.safeDrawing` (status bar / Dynamic Island, home indicator), for screens that lay
    /// themselves out edge to edge and pad exactly where Compose applies `windowInsetsPadding(safeDrawing)`.
    var safeDrawingInsets: EdgeInsets {
        get { self[SafeDrawingInsetsKey.self] }
        set { self[SafeDrawingInsetsKey.self] = newValue }
    }

    /// False while a destination is covered but kept alive (hidden): its ambient animations pause.
    var routeActive: Bool {
        get { self[RouteActiveKey.self] }
        set { self[RouteActiveKey.self] = newValue }
    }
}

/// Window safe-area insets, used if SwiftUI reports none (e.g. before the first layout pass).
@MainActor
private func windowSafeInsets() -> EdgeInsets {
    let scene = UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
    guard let i = scene?.keyWindow?.safeAreaInsets ?? scene?.windows.first?.safeAreaInsets else { return EdgeInsets() }
    return EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right)
}

// MARK: - Easing

/// Compose `CubicBezierEasing` (used for tween-driven values computed per frame, e.g. FastOutSlowIn, EaseInOutSine).
struct ComposeCubicBezier {
    let x1: Double, y1: Double, x2: Double, y2: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    static let FastOutSlowIn = ComposeCubicBezier(0.4, 0, 0.2, 1)
    static let EaseInOutSine = ComposeCubicBezier(0.37, 0, 0.63, 1)

    @inline(__always)
    private static func bez(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }

    @inline(__always)
    private static func slope(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * p1 + 6 * u * t * (p2 - p1) + 3 * t * t * (1 - p2)
    }

    func transform(_ fraction: Float) -> Float {
        let x = Double(fraction)
        if x <= 0 || x >= 1 { return fraction }
        var t = x
        for _ in 0..<8 {
            let err = Self.bez(t, x1, x2) - x
            if Swift.abs(err) < 1e-7 { return Float(Self.bez(t, y1, y2)) }
            let d = Self.slope(t, x1, x2)
            if Swift.abs(d) < 1e-6 { break }
            t -= err / d
        }
        var lo = 0.0, hi = 1.0
        t = x
        for _ in 0..<40 {
            let xt = Self.bez(t, x1, x2)
            if Swift.abs(xt - x) < 1e-7 { break }
            if xt < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return Float(Self.bez(t, y1, y2))
    }
}

// MARK: - Root (Kotlin SweetPopApp composable + MainActivity lifecycle)

struct SweetPopRoot: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = Router(start: .splash)

    var body: some View {
        ThemeHost(content: NavHost(router: router))
            .onChange(of: scenePhase, initial: true) { _, phase in
                // MainActivity.onStart / onStop.
                switch phase {
                case .active:
                    container.audio.onStart()
                    container.save.refreshLives()
                case .background:
                    container.audio.onStop()
                default:
                    break
                }
            }
    }
}

/// `SweetPopTheme(themeMode = save.theme)`: only this view depends on the saved state, so a save change
/// doesn't rebuild the destinations.
private struct ThemeHost<Content: View>: View {
    let content: Content

    @Environment(AppContainer.self) private var container

    var body: some View {
        SweetPopTheme(themeMode: container.save.state.theme) { content }
    }
}

/// Global backdrop + the back stack's destinations (Kotlin `Box { Backdrop(…); NavHost(…) }`).
private struct NavHost: View {
    let router: Router

    @Environment(AppContainer.self) private var container

    var body: some View {
        GeometryReader { geo in
            let reported = geo.safeAreaInsets
            let insets = reported.top > 0 || reported.bottom > 0 ? reported : windowSafeInsets()
            ZStack {
                let route = router.current
                Backdrop(
                    raysCenterY: route.pattern == Routes.SPLASH ? 0.6 : 0.66,
                    subtle: route.pattern == Routes.GAME
                )
                .ignoresSafeArea()

                let topId = router.top.id
                ForEach(router.stack.filter(\.mounted)) { entry in
                    let isTop = entry.id == topId
                    destination(entry.route)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(entry.hidden ? 0 : 1)
                        .scaleEffect(entry.scale)
                        .allowsHitTesting(isTop && !entry.hidden)
                        .accessibilityHidden(!isTop)
                        .environment(\.routeActive, isTop && !entry.hidden)
                        .transition(.route)
                        .zIndex(entry.z)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.safeDrawingInsets, insets)
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .splash:
            SplashScreen(onDone: {
                #if DEBUG
                // QA shortcut (debug builds only): launch with `-SPRoute home|settings|game:N|doc:terms|doc:privacy|onboarding|debug`
                // to land on a screen after the normal splash prewarm, for screenshot checks.
                if let target = DebugLaunch.route {
                    if target != .onboarding(replay: false) { container.save.completeOnboarding() }
                    router.navigate(.home, popUpTo: Routes.SPLASH, inclusive: true)
                    if target != .home { router.navigate(target) }
                    return
                }
                #endif
                let next: Route = container.save.state.onboardingDone ? .home : .onboarding(replay: false)
                router.navigate(next, popUpTo: Routes.SPLASH, inclusive: true)
            })
        case .onboarding(let replay):
            OnboardingScreen(
                onFinish: {
                    container.save.completeOnboarding()
                    if replay {
                        router.popBackStack()
                    } else {
                        router.navigate(.home, popUpTo: Routes.ONBOARDING, inclusive: true)
                    }
                },
                onOpenDoc: { router.navigate(.doc(kind: $0)) }
            )
        case .home:
            HomeScreen(
                onPlay: { n in router.navigate(.game(level: n), launchSingleTop: true) },
                onSettings: { router.navigate(.settings, launchSingleTop: true) }
            )
        case .game(let level):
            GameScreen(
                levelNumber: level,
                onMap: { router.popBackStack(Routes.HOME, inclusive: false) },
                onNextLevel: { n in router.navigate(.game(level: n), popUpTo: Routes.HOME) }
            )
        case .settings:
            SettingsScreen(
                onBack: { router.popBackStack() },
                onReplayTutorial: { router.navigate(.onboarding(replay: true)) },
                onDocument: { router.navigate(.doc(kind: $0)) },
                onDebug: { router.navigate(.debug) }
            )
        case .doc(let kind):
            DocumentScreen(kind, onBack: { router.popBackStack() })
        case .debug:
            #if DEBUG
            DebugScreen(onBack: { router.popBackStack() })
            #else
            Color.clear
            #endif
        }
    }
}

#if DEBUG
/// Debug-only launch routing for automated screenshot checks (`-SPRoute game:5`).
enum DebugLaunch {
    static var route: Route? {
        guard let raw = UserDefaults.standard.string(forKey: "SPRoute") else { return nil }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts[0] {
        case "home": return .home
        case "settings": return .settings
        case "onboarding": return .onboarding(replay: false)
        case "debug": return .debug
        case "doc": return .doc(kind: parts.count > 1 ? parts[1] : "terms")
        case "game": return .game(level: parts.count > 1 ? Int(parts[1]) ?? 1 : 1)
        default: return nil
        }
    }
}
#endif
