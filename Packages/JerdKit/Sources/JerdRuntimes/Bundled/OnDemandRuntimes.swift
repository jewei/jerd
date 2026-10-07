import Foundation
import JerdFoundation
import JerdManifest

/// The pinned runtimes that the app bundle does not embed (the database engines).
///
/// The app installs one only after a user action, through `RuntimeInstaller`, from exactly its pin
/// in the bundled catalog: the URL, the exact size, the SHA-256, and for MySQL the reviewed
/// signature file. It uses the same pipeline and preparers as `./dev runtimes prepare`.
public struct OnDemandRuntimes: Sendable {
    let source: BundledPayloadSource

    /// - Parameter resources: `Jerd.app/Contents/Resources/RuntimePayloads`.
    public init(resources: URL, architecture: CPUArchitecture = .current) {
        source = BundledPayloadSource(root: resources, architecture: architecture)
    }

    /// The release of every on-demand pin, in catalog order.
    /// - Throws: `.unavailable` when the app bundle has no runtime catalog; `.invalid` for a bad one.
    public func releases() throws -> [RuntimeRelease] {
        let catalog = try source.catalog()
        return try catalog.onDemandPins.map {
            try $0.release(architecture: catalog.architecture, catalogDirectory: nil)
        }
    }

    /// The pinned release of `kind`, or nil when the app embeds the kind or has no pin of it.
    public func release(for kind: RuntimeKind) throws -> RuntimeRelease? {
        try releases().first { $0.kind == kind }
    }
}
