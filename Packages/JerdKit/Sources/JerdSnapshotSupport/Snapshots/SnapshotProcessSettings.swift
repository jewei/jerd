import Foundation

/// The user settings that change how AppKit draws, fixed to the macOS defaults for the
/// snapshot process. Images then do not depend on the accent color, scroll bar, sidebar size,
/// language, or region settings of the developer who renders them.
///
/// The values go into the argument domain of `UserDefaults`, which wins over the global
/// domain. AppKit reads them once, when the application starts, so `apply(contrast:)` must
/// run before the first use of `NSApplication.shared`. Only the snapshot process does this.
package enum SnapshotProcessSettings {
    /// The fixed values. The blue accent and highlight equal the "Multicolor" default for an
    /// app without its own accent color.
    package static func overrides(contrast: SnapshotContrast) -> [String: Any] {
        [
            "AppleAccentColor": 4,
            "AppleAquaColorVariant": 1,
            "AppleHighlightColor": "0.698039 0.843137 1.000000 Blue",
            "AppleShowScrollBars": "WhenScrolling",
            "NSTableViewDefaultSizeMode": 2,
            "AppleLocale": "en_US",
            "AppleLanguages": ["en-US"],
            "AppleInterfaceStyle": "Light",
            // The key of the Increase Contrast setting in Accessibility > Display.
            "increaseContrast": contrast == .increased,
        ]
    }

    /// The argument domain with the fixed values over `existing`, so other `-Key value`
    /// arguments stay.
    package static func argumentDomain(merging existing: [String: Any], contrast: SnapshotContrast) -> [String: Any] {
        existing.merging(overrides(contrast: contrast)) { _, fixed in fixed }
    }

    /// Writes the fixed values into the argument domain of `UserDefaults.standard`.
    package static func apply(contrast: SnapshotContrast) {
        let defaults = UserDefaults.standard
        let existing = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(
            argumentDomain(merging: existing, contrast: contrast), forName: UserDefaults.argumentDomain)
    }
}
