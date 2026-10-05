import AppKit

/// Measures rendered pixels: colors, WCAG contrast, and equal regions of two images.
struct PixelMeasure {
    let image: NSBitmapImageRep

    var width: Int { image.pixelsWide }
    var height: Int { image.pixelsHigh }

    /// The sRGB components of one pixel, from 0 to 255.
    func color(x: Int, y: Int) -> [Int] {
        guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return [0, 0, 0] }
        return [color.redComponent, color.greenComponent, color.blueComponent].map { Int(($0 * 255).rounded()) }
    }

    /// The most frequent color in a region, for example the bezel of a button.
    func dominantColor(columns: Range<Int>, rows: Range<Int>) -> [Int] {
        var counts: [[Int]: Int] = [:]
        for y in rows {
            for x in columns {
                counts[color(x: x, y: y), default: 0] += 1
            }
        }
        return counts.max { $0.value < $1.value }?.key ?? []
    }

    /// The highest WCAG contrast ratio between any pixel of a region and `background`.
    func maximumContrast(columns: Range<Int>, rows: Range<Int>, against background: [Int]) -> Double {
        var best = 1.0
        for y in rows {
            for x in columns {
                best = max(best, Self.contrastRatio(color(x: x, y: y), background))
            }
        }
        return best
    }

    /// Whether `other` has the same bytes in the given pixel rows, counted from the top.
    func sameRows(_ rows: Range<Int>, as other: PixelMeasure) -> Bool {
        guard image.bytesPerRow == other.image.bytesPerRow, height == other.height,
            let first = image.bitmapData, let second = other.image.bitmapData
        else { return false }
        let offset = rows.lowerBound * image.bytesPerRow
        return memcmp(first + offset, second + offset, rows.count * image.bytesPerRow) == 0
    }

    /// Whether `other` has the same colors in the given pixel columns, in every row.
    func sameColumns(_ columns: Range<Int>, as other: PixelMeasure) -> Bool {
        guard height == other.height else { return false }
        for y in 0..<height {
            for x in columns where color(x: x, y: y) != other.color(x: x, y: y) {
                return false
            }
        }
        return true
    }

    /// The WCAG 2 contrast ratio of two sRGB colors.
    static func contrastRatio(_ first: [Int], _ second: [Int]) -> Double {
        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ color: [Int]) -> Double {
        let linear = color.map { component -> Double in
            let value = Double(component) / 255
            return value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        guard linear.count == 3 else { return 0 }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
}
