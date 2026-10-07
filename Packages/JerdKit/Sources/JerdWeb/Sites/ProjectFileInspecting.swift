/// Reads project folders for site validation. Tests use a fake file set.
public protocol ProjectFileInspecting: Sendable {
    /// The canonical form of an existing directory.
    /// - Throws: `.invalid` for a relative path, a control character, or a missing directory.
    func canonicalDirectory(_ path: String) throws -> String
    /// True when an item exists at `path` (links followed) and is not a directory.
    func isFile(_ path: String) -> Bool
}
