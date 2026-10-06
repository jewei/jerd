import AppKit
import JerdUI

/// The icon images of the fixtures: small copies of the shipped app icons, so snapshots show
/// the real designs without the app bundle.
@MainActor
public final class BundleIconImages: AppIconImageProviding {
    private var cache: [AppIconChoice: NSImage] = [:]

    public init() {}

    public func image(for choice: AppIconChoice) -> NSImage? {
        if let cached = cache[choice] { return cached }
        guard
            let url = Bundle.module.url(forResource: choice.imageName, withExtension: "png", subdirectory: "AppIcons"),
            let image = NSImage(contentsOf: url)
        else { return nil }
        cache[choice] = image
        return image
    }
}
