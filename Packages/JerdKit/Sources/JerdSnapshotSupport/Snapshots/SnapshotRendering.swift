import Foundation

/// One rendered PNG of a catalog entry.
package struct SnapshotRendering: Sendable {
    package let fileName: String
    package let pngData: Data
}
