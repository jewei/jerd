import AppKit
import Observation

/// The menu bar, Dock, and icon choices. Each change is saved and applied at once; there is
/// no Save button. Both switches can be off: Jerd then opens its window when the user opens
/// it again from Applications (`AppState.reopen()`), and the page says so.
@MainActor
@Observable
public final class AppearanceModel {
    public var showMenuBar: Bool {
        didSet { defaults.setShowMenuBar(showMenuBar) }
    }

    public var showDock: Bool {
        didSet {
            defaults.setShowDock(showDock)
            presence.showInDock(showDock)
        }
    }

    public var icon: AppIconChoice {
        didSet {
            defaults.setIcon(icon)
            presence.useIcon(icon)
        }
    }

    @ObservationIgnored private let defaults: AppearanceDefaults
    @ObservationIgnored private let presence: any AppPresenceApplying
    @ObservationIgnored private let images: any AppIconImageProviding

    public init(
        defaults: AppearanceDefaults, presence: any AppPresenceApplying, images: any AppIconImageProviding
    ) {
        self.defaults = defaults
        self.presence = presence
        self.images = images
        showMenuBar = defaults.showMenuBar
        showDock = defaults.showDock
        icon = defaults.icon
    }

    /// Applies the saved Dock and icon choices. The app calls it at launch, before any window
    /// shows, so a hidden Dock icon never flashes.
    public func apply() {
        presence.showInDock(showDock)
        presence.useIcon(icon)
    }

    /// True when Jerd has neither a menu bar icon nor a Dock icon.
    public var isHiddenEverywhere: Bool { !showMenuBar && !showDock }

    /// The image of a design, for the icon picker and About.
    public func image(for choice: AppIconChoice) -> NSImage? {
        images.image(for: choice)
    }
}
