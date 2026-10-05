import Foundation

/// One rendered PNG of a catalog entry.
package struct SnapshotRendering: Sendable {
    package let fileName: String
    package let pngData: Data
}

extension SnapshotRenderer {
    /// Renders an entry at every size, in each of its appearances.
    package func renderings(of entry: SnapshotEntry) throws -> [SnapshotRendering] {
        var result: [SnapshotRendering] = []
        for size in entry.sizes {
            for appearance in entry.appearances {
                let data = try renderPNG(entry.makeView(), size: size, appearance: appearance, chrome: entry.chrome)
                result.append(
                    SnapshotRendering(fileName: entry.fileName(appearance: appearance, size: size), pngData: data))
            }
        }
        return result
    }
}
