import AppKit

extension SnapshotRenderer {
    /// Draws `view` into a new sRGB bitmap at the snapshot scale.
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
        view.cacheDisplay(in: bounds, to: image)
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
