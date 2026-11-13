import Foundation

/// Port of Kotlin `core.Platform`. Only `versionName` carries over; Android's `openStorePage(context)`
/// (market:// intent with a Play Store web fallback) has no engine-side equivalent: the UI opens the
/// App Store page with GameKit `AppLinks.open(_:)` once the App Store id is known.
enum Platform {
    /// Kotlin `BuildConfig.VERSION_NAME` → the bundle's marketing version.
    static var versionName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
