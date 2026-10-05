import JerdFoundation

/// Every error that archive extraction and tree copies throw. The texts are user-visible.
public enum ArchiveFailure {
    // Library and archive level.
    public static let libraryUnsupported = JerdError.unavailable("The system archive library is not supported.")
    public static let cannotOpen = JerdError.unavailable("Cannot open the runtime archive.")
    public static let unreadable = JerdError.invalid("The runtime archive cannot be read.")
    public static let invalidEntry = JerdError.invalid("The runtime archive has an invalid entry.")
    public static let tooManyEntries = JerdError.invalid("The runtime archive has too many files.")
    public static let damaged = JerdError.invalid("The runtime archive is damaged.")

    // Entry names and types.
    public static let unsafePath = JerdError.invalid("The archive contains an unsafe path.")
    public static let moreThanOneRoot = JerdError.invalid("The runtime archive has more than one root.")
    public static let rootNotDirectory = JerdError.invalid("The runtime archive root is not a directory.")
    public static let unsupportedType = JerdError.invalid("The runtime archive has an unsupported file type.")
    public static let duplicatePath = JerdError.invalid("The archive contains duplicate file paths.")

    // Links.
    public static let unsafeLink = JerdError.invalid("An archive link is unsafe.")
    public static let linkLeavesRoot = JerdError.invalid("An archive link leaves its root.")
    public static let emptyLink = JerdError.invalid("An archive link is empty.")
    public static let linkCycle = JerdError.invalid("The archive has a link cycle.")
    public static let linkTargetMissing = JerdError.invalid("An archive link does not refer to an included file.")

    // Sizes.
    public static let fileTooLarge = JerdError.invalid("An archive file exceeds its size limit.")
    public static let outputTooLarge = JerdError.invalid("The runtime archive exceeds its size limit.")
    public static let outputTooLargeAfterLinks = JerdError.invalid(
        "The runtime archive exceeds its size limit after copying links.")
    public static let exceedsDeclaredSize = JerdError.invalid("An archive file exceeds its declared size.")
    public static let incomplete = JerdError.invalid("An archive file is incomplete.")

    // Output files.
    public static let cannotCreateFile = JerdError.invalid("Cannot create an archive file.")
    public static let cannotWriteFile = JerdError.unavailable("Cannot write an archive file.")

    // Contained tree copies.
    public static let treeLinkLeavesRoot = JerdError.invalid("A runtime file link leaves its directory.")
    public static let treeTooManyFiles = JerdError.invalid("The runtime contains too many files.")
    public static let treeCycle = JerdError.invalid("The runtime contains a directory link cycle.")
    public static let treeInvalidFile = JerdError.invalid("A runtime file is invalid.")
    public static let treeUnreadable = JerdError.invalid("The runtime files cannot be read.")
}
