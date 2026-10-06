import AppKit
import JerdUI

/// The images of the shipped icon designs, read once from the app bundle and cached. The app
/// target copies them to `Contents/Resources/AppIcons/Icon-<choice>.png`.
@MainActor
public final class AppIconImages: AppIconImageProviding {
    /// The menu bar icon size, in points.
    public static let menuBarSize = NSSize(width: 18, height: 18)
    static let folder = "AppIcons"

    private let bundle: Bundle
    private var images: [AppIconChoice: NSImage] = [:]
    private var menuBarImages: [AppIconChoice: NSImage] = [:]

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    public func image(for choice: AppIconChoice) -> NSImage? {
        if let cached = images[choice] { return cached }
        guard let url = Self.url(of: choice, in: bundle), let image = NSImage(contentsOf: url) else { return nil }
        images[choice] = image
        return image
    }

    /// A full-color copy at the menu bar size. It is not a template image, so the menu bar
    /// shows the design's own colors.
    public func menuBarImage(for choice: AppIconChoice) -> NSImage? {
        if let cached = menuBarImages[choice] { return cached }
        guard let image = image(for: choice) else { return nil }
        let small = NSImage(size: Self.menuBarSize, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
        small.isTemplate = false
        small.accessibilityDescription = "Jerd"
        menuBarImages[choice] = small
        return small
    }

    /// The image in the `AppIcons` folder, or at the resources root as older builds kept it.
    static func url(of choice: AppIconChoice, in bundle: Bundle) -> URL? {
        bundle.url(forResource: choice.imageName, withExtension: "png", subdirectory: folder)
            ?? bundle.url(forResource: choice.imageName, withExtension: "png")
    }
}
