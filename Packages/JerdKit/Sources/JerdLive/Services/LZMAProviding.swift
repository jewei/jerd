import JerdRuntimes

/// The reviewed XZ library of the app, for the RustFS preparation. `BundledRuntimeBootstrap` is the
/// live type: it verifies the library against its receipt in the app bundle.
package protocol LZMAProviding: Sendable {
    /// The library, or nil in a development build without it.
    func bundledLZMA() async throws -> SupportLibrary?
}

extension BundledRuntimeBootstrap: LZMAProviding {}
