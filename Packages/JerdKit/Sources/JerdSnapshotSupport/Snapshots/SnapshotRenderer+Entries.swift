import Foundation

extension SnapshotRenderer {
    /// Renders an entry at every size, in those of its appearances that `contrast` allows.
    /// One process renders only one contrast setting; see `SnapshotContrast`.
    package func renderings(of entry: SnapshotEntry, contrast: SnapshotContrast) async throws -> [SnapshotRendering] {
        var result: [SnapshotRendering] = []
        for size in entry.sizes {
            for appearance in entry.appearances where appearance.contrast == contrast {
                let fileName = entry.fileName(appearance: appearance, size: size)
                let data = try await renderPNG(
                    entry.makeView(), size: size, appearance: appearance, chrome: entry.chrome, scroll: entry.scroll,
                    name: fileName, isReady: entry.isReady)
                result.append(SnapshotRendering(fileName: fileName, pngData: data))
            }
        }
        return result
    }
}
