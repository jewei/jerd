import Foundation

/// The folder that receives the PNG files. After a full run it removes PNG files that no
/// catalog entry writes any more, so a renamed or removed page leaves no image that looks current.
package struct SnapshotOutputFolder: Sendable {
    package let url: URL

    package init(url: URL) {
        self.url = url
    }

    package func create() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    package func write(_ rendering: SnapshotRendering) throws {
        try rendering.pngData.write(to: url.appending(path: rendering.fileName), options: .atomic)
    }

    /// Removes the PNG files whose names are not in `current`. Other files and folders stay.
    /// - Returns: The removed file names, sorted.
    package func removeStalePNGs(keeping current: Set<String>) throws -> [String] {
        let names = try FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))
        let stale = names.filter { $0.hasSuffix(".png") && !current.contains($0) }.sorted()
        for name in stale {
            try FileManager.default.removeItem(at: url.appending(path: name))
        }
        return stale
    }
}
