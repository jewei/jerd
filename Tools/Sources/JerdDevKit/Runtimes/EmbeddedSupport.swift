import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes

/// The support libraries that the app embeds beside the payloads: the XZ library that the RustFS
/// preparation needs. The app installs RustFS on demand, so the library is no longer inside a
/// RustFS payload; it has its own folder `RuntimePayloads/support/xz` with its receipt.
///
/// One rule for the build, the release, and `./dev runtimes verify`: the app embeds every support
/// source of the catalog that the app uses (today only `xz`). The build copies it, the release
/// requires, signs, and checks it, and an app with any other support folder is refused.
enum EmbeddedSupport {
    /// The state of one support folder.
    enum State: Equatable, Sendable {
        case missing
        case valid(SupportReceipt)
        case invalid(String)
    }

    /// The embedded support names of `catalog`, sorted.
    static func names(_ catalog: RuntimePinCatalog) -> [String] {
        catalog.supportSources.keys.filter { $0 == BundledSupportLibrary.xzName }.sorted()
    }

    /// The files that a support folder must hold besides its receipt.
    static func requiredFiles(_ name: String) -> Set<String> {
        name == BundledSupportLibrary.xzName ? BundledSupportLibrary.xzFiles : []
    }

    /// The prepared folder in the repository: `.build/runtimes/support/<name>`.
    static func preparedFolder(_ name: String, in repository: Repository) -> URL {
        repository.runtimeSupport.appending(path: name, directoryHint: .isDirectory)
    }

    /// The state of `folder` against the pinned source of `name`. With `deploymentTarget`, the
    /// receipt must also record that target (the prepared folder); the release checks the built
    /// files with `otool` instead.
    static func state(
        of name: String, in folder: URL, catalog: RuntimePinCatalog, deploymentTarget: String? = nil
    ) -> State {
        guard FileProbe.presence(at: folder).mayExist else { return .missing }
        do {
            guard let receipt = try SupportReceipt.read(from: folder) else {
                return .invalid("The \(name) support folder has no receipt.")
            }
            guard let source = catalog.supportSources[name], receipt.name == name,
                receipt.matches(source, deploymentTarget: deploymentTarget)
            else { return .invalid("The \(name) support receipt does not match its pin or the deployment target.") }
            guard Set(receipt.files.keys) == requiredFiles(name) else {
                return .invalid("The \(name) support folder does not hold exactly \(requiredFiles(name).sorted()).")
            }
            try receipt.verify(in: folder)
            return .valid(receipt)
        } catch {
            return .invalid(PayloadInventory.message(of: error))
        }
    }

    /// The valid receipt of each embedded support folder below `root` (an app's `RuntimePayloads`).
    /// - Throws: when one is missing or invalid.
    static func verified(
        in root: URL, catalog: RuntimePinCatalog
    ) throws -> [(name: String, folder: URL, receipt: SupportReceipt)] {
        try names(catalog).map { name in
            let folder = BundledSupportLibrary.folder(name, in: root)
            switch state(of: name, in: folder, catalog: catalog) {
            case .valid(let receipt): return (name, folder, receipt)
            case .missing: throw DevFailure.checkFailed("The app has no \(name) support library.")
            case .invalid(let message): throw DevFailure.checkFailed("The \(name) support library: \(message)")
            }
        }
    }
}
