import AppKit
import JerdDesign

/// A window that reports itself as key and main while it stays offscreen. Controls then draw
/// in their active state (accent colors and colored window buttons) as a user sees them.
final class ActiveWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // AppKit asks these to choose the active control appearance. Only snapshots use this class.
    @objc func _hasActiveAppearance() -> Bool { true }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    @objc func _hasKeyAppearance() -> Bool { true }
    @objc func _hasMainAppearance() -> Bool { true }
    @objc func _hasActiveControls() -> Bool { true }
    @objc func hasKeyAppearance() -> Bool { true }
    @objc func hasMainAppearance() -> Bool { true }
}
