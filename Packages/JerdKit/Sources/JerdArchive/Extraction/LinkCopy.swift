import Darwin
import JerdFoundation

/// A link to materialize: copy the extracted regular file `source` to `path`.
package struct LinkCopy: Sendable, Equatable {
    package let path: RelativePath
    package let source: RelativePath
}
