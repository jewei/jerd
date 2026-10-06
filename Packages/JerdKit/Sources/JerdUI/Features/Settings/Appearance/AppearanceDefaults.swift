import Foundation

/// The one reader and writer of the appearance keys in the `dev.jerd.app` defaults domain.
/// The keys and value forms are a compatibility contract.
public struct AppearanceDefaults {
    public static let showMenuBarKey = "showMenuBar"
    public static let showDockKey = "showDock"
    public static let appIconKey = "appIcon"

    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The menu bar extra shows unless the user turned it off.
    public var showMenuBar: Bool {
        defaults.object(forKey: Self.showMenuBarKey) as? Bool ?? true
    }

    /// The Dock icon shows unless the user turned it off.
    public var showDock: Bool {
        defaults.object(forKey: Self.showDockKey) as? Bool ?? true
    }

    /// The selected icon. Old and unknown values read as Rainbow hook, without a rewrite.
    public var icon: AppIconChoice {
        AppIconChoice(storedValue: defaults.string(forKey: Self.appIconKey))
    }

    public func setShowMenuBar(_ value: Bool) {
        defaults.set(value, forKey: Self.showMenuBarKey)
    }

    public func setShowDock(_ value: Bool) {
        defaults.set(value, forKey: Self.showDockKey)
    }

    public func setIcon(_ value: AppIconChoice) {
        defaults.set(value.rawValue, forKey: Self.appIconKey)
    }
}
