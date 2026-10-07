import Foundation

/// Inputs that some preparations need from other installed runtimes.
public struct PreparationTools: Sendable {
    /// A PHP CLI executable, for Composer and the Laravel installer.
    public var phpCLI: URL?
    /// A `composer.phar`, for the Laravel installer.
    public var composer: URL?
    /// The reviewed XZ library for RustFS builds that link Homebrew's `liblzma`.
    public var lzma: SupportLibrary?

    public init(phpCLI: URL? = nil, composer: URL? = nil, lzma: SupportLibrary? = nil) {
        self.phpCLI = phpCLI
        self.composer = composer
        self.lzma = lzma
    }
}
