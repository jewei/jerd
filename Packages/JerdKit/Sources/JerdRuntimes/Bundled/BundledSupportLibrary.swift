import Foundation
import JerdFoundation
import JerdManifest

/// The reviewed XZ library that the app embeds on its own, for the RustFS preparation:
/// `RuntimePayloads/support/xz/` with `liblzma.5.dylib`, `XZ-LICENSE.txt`, and `support-receipt.json`.
///
/// The app does not embed RustFS (it installs it on demand), but upstream RustFS links Homebrew's
/// `liblzma`, so the preparation copies this library into the installed runtime (`LZMALinker`).
/// The receipt must name the pinned XZ source of the bundled catalog, and every file must match it.
public struct BundledSupportLibrary: Sendable {
    /// The folder below `RuntimePayloads` that holds the support libraries.
    public static let folderName = "support"
    /// The name of the XZ support source in the pin catalog and of its folder.
    public static let xzName = "xz"
    /// The files of the XZ folder besides its receipt.
    public static let xzFiles: Set<String> = [LZMALinker.libraryName, LZMALinker.licenseName]

    let root: URL

    /// - Parameter root: `Jerd.app/Contents/Resources/RuntimePayloads`.
    public init(root: URL) {
        self.root = root
    }

    /// `<root>/support/<name>`.
    public static func folder(_ name: String, in root: URL) -> URL {
        root.appendingPathComponent(folderName, isDirectory: true).appendingPathComponent(name, isDirectory: true)
    }

    /// The verified XZ library, or nil when the bundle has no XZ folder (a development build).
    /// - Throws: `.invalid` when the folder does not match its receipt or the pinned XZ source.
    public func xz(catalog: RuntimePinCatalog) throws -> SupportLibrary? {
        let folder = Self.folder(Self.xzName, in: root)
        guard FileProbe.presence(at: folder).mayExist else { return nil }
        let receipt = try SupportReceipt.decode(
            BundleFile.read(folder.appendingPathComponent(SupportReceipt.fileName), limit: SupportReceipt.sizeLimit))
        guard let source = catalog.supportSources[Self.xzName], receipt.name == Self.xzName, receipt.matches(source),
            Set(receipt.files.keys) == Self.xzFiles
        else { throw JerdError.invalid("The bundled XZ library does not match its pin.") }
        try receipt.verify(in: folder)
        return SupportLibrary(
            library: folder.appendingPathComponent(LZMALinker.libraryName),
            license: folder.appendingPathComponent(LZMALinker.licenseName))
    }
}
