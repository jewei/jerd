import Foundation

/// A support library file and its license, copied into a payload beside the binary that needs it.
public struct SupportLibrary: Sendable, Equatable {
    /// The library, for example `liblzma.5.dylib`.
    public let library: URL
    /// Its license text, copied as `XZ-LICENSE.txt` for XZ.
    public let license: URL

    public init(library: URL, license: URL) {
        self.library = library
        self.license = license
    }
}
