import Foundation
import JerdFoundation

/// Reads the free space of the volume that holds a folder. `VolumeFreeSpace` is the live type.
package protocol FreeSpaceReading: Sendable {
    /// The bytes available for important use on the volume of `url` (or of its nearest existing
    /// parent), or nil when the system cannot tell.
    func availableBytes(near url: URL) -> Int64?
}

/// The live free-space reader: the volume capacity for important use, as Finder reports it.
package struct VolumeFreeSpace: FreeSpaceReading {
    package init() {}

    package func availableBytes(near url: URL) -> Int64? {
        var folder = url.standardizedFileURL
        while FileProbe.presence(at: folder) == .absent, folder.path != "/" {
            folder.deleteLastPathComponent()
        }
        let key = URLResourceKey.volumeAvailableCapacityForImportantUsageKey
        do {
            return try folder.resourceValues(forKeys: [key]).volumeAvailableCapacityForImportantUsage
        } catch {
            // No answer is not a refusal: the installation still stops cleanly on a full disk.
            return nil
        }
    }
}
