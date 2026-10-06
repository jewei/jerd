import AppKit

extension SnapshotRenderer {
    /// Draws `view` into a new sRGB bitmap at the snapshot scale.
    ///
    /// The capture uses `displayIgnoringOpacity(_:in:)`, not `cacheDisplay(in:to:)`, so it only
    /// reads the window. `cacheDisplay` changes an AppKit drawing property while it draws. The
    /// AppKit controls that SwiftUI hosts (window buttons, a segmented toolbar picker) can track
    /// that property, and then they lay out and render again in the capture, with different text
    /// bounds. Whether a control tracks it depends on the timing of its first render, so two
    /// renderings of one view could have different bytes.
    func capture(_ view: NSView) -> NSBitmapImageRep? {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
            let image = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width * Self.scale),
                pixelsHigh: Int(bounds.height * Self.scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        image.size = bounds.size
        guard let context = NSGraphicsContext(bitmapImageRep: image) else { return nil }
        view.displayIgnoringOpacity(bounds, in: context)
        return image.retagging(with: .sRGB) ?? image
    }

    /// Whether two captures have the same size and the same bytes.
    static func samePixels(_ first: NSBitmapImageRep, _ second: NSBitmapImageRep) -> Bool {
        guard first.pixelsWide == second.pixelsWide, first.pixelsHigh == second.pixelsHigh,
            first.bytesPerRow == second.bytesPerRow,
            let firstBytes = first.bitmapData, let secondBytes = second.bitmapData
        else { return false }
        return memcmp(firstBytes, secondBytes, first.bytesPerRow * first.pixelsHigh) == 0
    }
}
