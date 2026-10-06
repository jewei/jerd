import AppKit

/// Supplies the image of each icon design. JerdLive reads the app bundle images
/// `Icon-<choice>.png` and caches them.
@MainActor
public protocol AppIconImageProviding: AnyObject {
    /// The image, or nil when the bundle has no image for the choice.
    func image(for choice: AppIconChoice) -> NSImage?
}
