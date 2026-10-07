import JerdFoundation

/// What to extract from an archive and the limits that protect the disk.
public struct ExtractionPolicy: Sendable {
    /// Requires one top folder shared by every entry and removes it from each path (A6).
    public var stripsRoot: Bool
    /// The maximum bytes written: selected files plus the copies made for links.
    public var outputLimit: Int64
    /// The maximum count of entries of any type, selected or not.
    public var entryLimit: Int
    /// The maximum size of one entry, selected or not.
    public var fileSizeLimit: Int64
    /// Chooses the files to extract. It receives the path after the root is removed.
    public var selects: @Sendable (RelativePath) -> Bool

    public static let defaultOutputLimit: Int64 = 2_000_000_000
    public static let defaultEntryLimit = 100_000
    public static let defaultFileSizeLimit: Int64 = 512_000_000

    public init(
        stripsRoot: Bool = false, outputLimit: Int64 = defaultOutputLimit,
        selects: @escaping @Sendable (RelativePath) -> Bool = { _ in true }
    ) {
        self.stripsRoot = stripsRoot
        self.outputLimit = outputLimit
        self.entryLimit = Self.defaultEntryLimit
        self.fileSizeLimit = Self.defaultFileSizeLimit
        self.selects = selects
    }
}
