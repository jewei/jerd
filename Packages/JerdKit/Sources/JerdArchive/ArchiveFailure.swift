import JerdFoundation

/// Every error that archive extraction and tree copies throw. The texts are user-visible.
package enum ArchiveFailure {
    // Library and archive level.
    package static let libraryUnsupported = JerdError.unavailable("The system archive library is not supported.")
    package static let cannotOpen = JerdError.unavailable("Cannot open the runtime archive.")
    package static let unreadable = JerdError.invalid("The runtime archive cannot be read.")
    package static let invalidEntry = JerdError.invalid("The runtime archive has an invalid entry.")
    package static let tooManyEntries = JerdError.invalid("The runtime archive has too many files.")
    package static let damaged = JerdError.invalid("The runtime archive is damaged.")

    // Entry names and types.
    package static let unsafePath = JerdError.invalid("The archive contains an unsafe path.")
    package static let moreThanOneRoot = JerdError.invalid("The runtime archive has more than one root.")
    package static let rootNotDirectory = JerdError.invalid("The runtime archive root is not a directory.")
    package static let unsupportedType = JerdError.invalid("The runtime archive has an unsupported file type.")
    package static let duplicatePath = JerdError.invalid("The archive contains duplicate file paths.")

    // Links.
    package static let unsafeLink = JerdError.invalid("An archive link is unsafe.")
    package static let linkLeavesRoot = JerdError.invalid("An archive link leaves its root.")
    package static let emptyLink = JerdError.invalid("An archive link is empty.")
    package static let linkCycle = JerdError.invalid("The archive has a link cycle.")
    package static let linkTargetMissing = JerdError.invalid("An archive link does not refer to an included file.")

    // Sizes.
    package static let fileTooLarge = JerdError.invalid("An archive file exceeds its size limit.")
    package static let outputTooLarge = JerdError.invalid("The runtime archive exceeds its size limit.")
    package static let outputTooLargeAfterLinks = JerdError.invalid(
        "The runtime archive exceeds its size limit after copying links.")
    package static let exceedsDeclaredSize = JerdError.invalid("An archive file exceeds its declared size.")
    package static let incomplete = JerdError.invalid("An archive file is incomplete.")

    // Output files.
    package static let cannotCreateFile = JerdError.invalid("Cannot create an archive file.")
    package static let cannotWriteFile = JerdError.unavailable("Cannot write an archive file.")

    // Contained tree copies.
    package static let treeLinkLeavesRoot = JerdError.invalid("A runtime file link leaves its directory.")
    package static let treeTooManyFiles = JerdError.invalid("The runtime contains too many files.")
    package static let treeCycle = JerdError.invalid("The runtime contains a directory link cycle.")
    package static let treeInvalidFile = JerdError.invalid("A runtime file is invalid.")
    package static let treeUnreadable = JerdError.invalid("The runtime files cannot be read.")
}
