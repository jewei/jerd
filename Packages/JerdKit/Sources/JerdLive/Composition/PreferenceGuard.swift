import Foundation

/// Keeps a Debug run on another data root from changing the user's `dev.jerd.app` preferences.
///
/// Jerd's own keys already go to the run's own domain (`LiveConfiguration.defaultsSuiteName`).
/// AppKit, SwiftUI, and Sparkle write their state to the app's standard domain, which a Debug
/// build shares with the user's Jerd: the menu bar item visibility (`NSStatusItem VisibleCC
/// Item-0`), the window frame (`NSWindow Frame main`), the sidebar width, and the update check
/// times. SwiftUI owns the status item and the window, so their autosave names cannot change.
/// So the guard copies the domain at launch and writes the copy back when the app quits
/// A Debug run that crashes keeps its changes.
@MainActor
public final class PreferenceGuard {
    private let domain: any PreferenceDomain
    private let saved: [String: Any]

    /// Copies the domain now. Create it before any scene, window, or status item exists.
    package init(domain: any PreferenceDomain) {
        self.domain = domain
        saved = domain.read()
    }

    /// The guard of a run on another data root, or nil for the user's own data root, whose
    /// window and menu bar state belong in the user's preferences.
    /// - Parameter domainName: The app's domain, `dev.jerd.app` in the app.
    public static func forRun(
        _ configuration: LiveConfiguration, domainName: String? = Bundle.main.bundleIdentifier
    ) -> PreferenceGuard? {
        guard configuration.defaultsSuiteName != nil, let name = domainName else { return nil }
        return PreferenceGuard(domain: UserDefaultsDomain(name: name))
    }

    /// Writes the copy back: changed keys get their old value, new keys go, and removed keys
    /// come back. Keys that did not change are not written.
    public func restore() {
        let current = domain.read()
        for key in current.keys where saved[key] == nil {
            domain.remove(key)
        }
        for (key, value) in saved where !Self.isEqual(current[key], value) {
            domain.write(value, for: key)
        }
    }

    private static func isEqual(_ left: Any?, _ right: Any) -> Bool {
        guard let left else { return false }
        return (left as AnyObject).isEqual(right as AnyObject)
    }
}
