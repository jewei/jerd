import AppKit

extension NSToolbar {
    /// The view of the first centered item: the section picker of the main window.
    package var centeredItemView: NSView? {
        items.first { centeredItemIdentifiers.contains($0.itemIdentifier) }?.view
    }
}
