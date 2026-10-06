import AppKit
import JerdUI

/// Applies the Dock and icon choices to the running app.
@MainActor
public final class AppPresence: AppPresenceApplying {
    private let images: any AppIconImageProviding

    public init(images: any AppIconImageProviding) {
        self.images = images
    }

    /// `.regular` shows the Dock icon and the app menu; `.accessory` hides both. The windows and
    /// the menu bar item stay.
    public func showInDock(_ isShown: Bool) {
        let policy = Self.activationPolicy(showInDock: isShown)
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    /// Changes the Dock icon while Jerd runs. Finder keeps the asset catalog icon.
    public func useIcon(_ icon: AppIconChoice) {
        guard let image = images.image(for: icon) else { return }
        NSApp.applicationIconImage = image
    }

    package static func activationPolicy(showInDock: Bool) -> NSApplication.ActivationPolicy {
        showInDock ? .regular : .accessory
    }
}
