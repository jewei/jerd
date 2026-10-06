import JerdFoundation
import JerdManifest

/// Compares the files of a folder with the files that a receipt records.
///
/// Finder metadata (`.DS_Store`) is skipped on both sides, so a receipt that records one still
/// matches a folder with or without it (RT-3).
public enum PayloadComparison {
    /// The paths that a message names at most.
    public static let reportedPathLimit = 8

    /// Requires exactly the expected hashes. Extra and missing files fail too.
    /// - Throws: `.invalid("The installed runtime changed: <paths>. Existing files were preserved.")`.
    public static func requireHashes(
        _ expected: [RelativePath: String], actual: [RelativePath: PayloadFileRecord]
    ) throws {
        try requireEqual(expected, actual.mapValues(\.sha256))
    }

    /// Requires exactly the expected hashes and executable flags.
    public static func requireRecords(
        _ expected: [RelativePath: PayloadFileRecord], actual: [RelativePath: PayloadFileRecord]
    ) throws {
        try requireEqual(expected, actual)
    }

    private static func requireEqual<Value: Equatable>(
        _ expected: [RelativePath: Value], _ actual: [RelativePath: Value]
    ) throws {
        let expected = FinderMetadata.removingMetadata(expected)
        let actual = FinderMetadata.removingMetadata(actual)
        let changed = Set(expected.keys).union(actual.keys).filter { expected[$0] != actual[$0] }
        guard !changed.isEmpty else { return }
        let names = changed.sorted().prefix(reportedPathLimit).map(\.string).joined(separator: ", ")
        throw JerdError.invalid("The installed runtime changed: \(names). Existing files were preserved.")
    }
}
