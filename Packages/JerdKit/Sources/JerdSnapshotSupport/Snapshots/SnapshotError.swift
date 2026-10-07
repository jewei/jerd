import CoreGraphics

/// A failure to produce a snapshot image. Each case names the file of the rendering.
package enum SnapshotError: Error, Equatable, CustomStringConvertible {
    case emptyImage(String)
    case encodingFailed(String)
    case sizeMismatch(String, expected: CGSize, actual: CGSize)
    case appearanceUnavailable(String, expected: String, actual: String)
    case notSettled(String, passes: Int)

    package var description: String {
        switch self {
        case .emptyImage(let file): "The snapshot \(file) has no pixels."
        case .encodingFailed(let file): "The snapshot \(file) could not be encoded as PNG."
        case .sizeMismatch(let file, let expected, let actual):
            "The snapshot \(file) rendered at \(Self.points(actual)) points, not at \(Self.points(expected))."
        case .appearanceUnavailable(let file, let expected, let actual):
            "The snapshot \(file) needs the appearance \(expected), but the window has \(actual). "
                + "Increase Contrast snapshots render only in the contrast pass of jerd-snapshots."
        case .notSettled(let file, let passes):
            "The snapshot \(file) was not ready or still changed after \(passes) layout passes."
        }
    }

    private static func points(_ size: CGSize) -> String {
        "\(Int(size.width))×\(Int(size.height))"
    }
}
