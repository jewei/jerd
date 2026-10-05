import Darwin
import JerdFoundation

/// What the extractor does with one archive entry, as decided by `ExtractionPlan`.
package enum EntryAction: Sendable, Equatable {
    /// Nothing: a directory, the stripped root, or an unselected entry.
    case skip
    /// A selected link. It becomes a copy of its final target after all entries are read.
    case recordLink(path: RelativePath, target: RelativePath)
    /// A selected regular file to write now from the entry data.
    case writeFile(FileWrite)
}
