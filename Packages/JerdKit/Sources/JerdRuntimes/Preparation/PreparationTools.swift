import Foundation

/// Inputs that some preparations need from other installed runtimes.
public struct PreparationTools: Sendable {
    /// A PHP CLI executable, for Composer and the Laravel installer.
    public var phpCLI: URL?
    /// A `composer.phar`, for the Laravel installer.
    public var composer: URL?
    /// The reviewed XZ library for RustFS builds that link Homebrew's `liblzma` (P-I1).
    public var lzma: SupportLibrary?

    public init(phpCLI: URL? = nil, composer: URL? = nil, lzma: SupportLibrary? = nil) {
        self.phpCLI = phpCLI
        self.composer = composer
        self.lzma = lzma
    }
}

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
