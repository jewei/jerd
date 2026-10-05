import JerdFoundation
import JerdManifest

/// Compares the files of a folder with the files that a receipt records.
public enum PayloadComparison {
    /// The paths that a message names at most.
    public static let reportedPathLimit = 8

    /// Requires exactly the expected hashes. Extra and missing files fail too.
    /// - Throws: `.invalid("The installed runtime changed: <paths>. Existing files were preserved.")`.
    public static func requireHashes(
        _ expected: [RelativePath: String], actual: [RelativePath: PayloadFileRecord]
    )
        throws
    {
        let changed = Set(expected.keys).union(actual.keys).filter { expected[$0] != actual[$0]?.sha256 }
        try report(changed)
    }

    /// Requires exactly the expected hashes and executable flags.
    public static func requireRecords(
        _ expected: [RelativePath: PayloadFileRecord], actual: [RelativePath: PayloadFileRecord]
    ) throws {
        let changed = Set(expected.keys).union(actual.keys).filter { expected[$0] != actual[$0] }
        try report(changed)
    }

    private static func report(_ changed: Set<RelativePath>) throws {
        guard !changed.isEmpty else { return }
        let names = changed.sorted().prefix(reportedPathLimit).map(\.string).joined(separator: ", ")
        throw JerdError.invalid("The installed runtime changed: \(names). Existing files were preserved.")
    }
}
