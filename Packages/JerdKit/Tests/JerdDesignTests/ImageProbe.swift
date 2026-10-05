import AppKit

/// Reads sampled pixels of a rendered image, so tests can prove an image has content.
struct ImageProbe {
    private let image: NSBitmapImageRep
    private let step: Int

    init(_ image: NSBitmapImageRep, step: Int = 7) {
        self.image = image
        self.step = step
    }

    /// The number of different colors on a sampled grid. A blank image has one.
    func distinctColorCount() -> Int {
        Set(samples().map { "\($0.red)-\($0.green)-\($0.blue)" }).count
    }

    /// The mean brightness of the sampled pixels, from 0 to 1.
    func averageBrightness() -> Double {
        let values = samples().map { ($0.red + $0.green + $0.blue) / 3 }
        return values.reduce(0, +) / Double(max(values.count, 1))
    }

    private func samples() -> [(red: Double, green: Double, blue: Double)] {
        var result: [(red: Double, green: Double, blue: Double)] = []
        for x in stride(from: 0, to: image.pixelsWide, by: step) {
            for y in stride(from: 0, to: image.pixelsHigh, by: step) {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let red = (color.redComponent * 255).rounded() / 255
                let green = (color.greenComponent * 255).rounded() / 255
                let blue = (color.blueComponent * 255).rounded() / 255
                result.append((red, green, blue))
            }
        }
        return result
    }
}
