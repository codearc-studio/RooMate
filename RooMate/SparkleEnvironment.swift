import SwiftUI

// Environment key that exposes a lightweight action to trigger Sparkle's "check for updates".
// We expose it as an optional closure to avoid importing Sparkle throughout the UI layer.
private struct SparkleCheckForUpdatesKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Call this to trigger a Sparkle update check. The closure is provided by the App entry point.
    var sparkleCheckForUpdates: (() -> Void)? {
        get { self[SparkleCheckForUpdatesKey.self] }
        set { self[SparkleCheckForUpdatesKey.self] = newValue }
    }
}
