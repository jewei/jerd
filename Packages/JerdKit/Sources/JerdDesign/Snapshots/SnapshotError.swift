import CoreGraphics

/// A failure to produce a snapshot image.
package enum SnapshotError: Error, Equatable, CustomStringConvertible {
    case emptyImage(String)
    case encodingFailed(String)
    case sizeMismatch(String, actual: CGSize)

    package var description: String {
        switch self {
        case .emptyImage(let name): "The snapshot \(name) has no pixels."
        case .encodingFailed(let name): "The snapshot \(name) could not be encoded as PNG."
        case .sizeMismatch(let name, let actual):
            "The snapshot \(name) rendered at \(Int(actual.width))×\(Int(actual.height)) points, not its set size."
        }
    }
}
