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

/// One regular file to write, with its mode and the byte limit that its data must respect.
package struct FileWrite: Sendable, Equatable {
    package let path: RelativePath
    /// 0700 when the entry has any execute bit, otherwise 0600.
    package let mode: mode_t
    /// The declared size. The data must have exactly this size. Nil when the archive does not record it.
    package let declaredSize: Int64?
    /// The most bytes that the data may have.
    package let byteLimit: Int64
    /// The error when the data has more than `byteLimit` bytes.
    package let limitFailure: JerdError
}

/// A link to materialize: copy the extracted regular file `source` to `path`.
package struct LinkCopy: Sendable, Equatable {
    package let path: RelativePath
    package let source: RelativePath
}
