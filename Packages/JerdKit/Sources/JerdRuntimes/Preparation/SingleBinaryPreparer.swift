import Foundation
import JerdArchive
import JerdFoundation
import JerdManifest

/// Caddy, Mailpit, cloudflared, and RustFS: one executable named like the kind, plus its license.
///
/// Caddy and Mailpit archives carry `LICENSE` and `README.md`. cloudflared and RustFS archives
/// carry only the binary, so their license comes from a pinned copy. A RustFS binary that links
/// Homebrew's `liblzma` gets the reviewed XZ library beside it.
package struct SingleBinaryPreparer: RuntimePreparing {
    package init() {}

    package func prepare(_ context: PreparationContext) async throws {
        let kind = context.release.kind
        let binary = kind.rawValue
        let license = try PinnedLicense.of(kind)
        let names: Set<String> = license == nil ? [binary, "LICENSE", "README.md"] : [binary]
        try await RuntimePreparers.extract(
            try context.requireArtifact(), to: context.payload,
            policy: ExtractionPolicy { names.contains($0.string) })
        try RuntimePreparers.requireFiles([binary], in: context.payload, kind: kind)
        if let license {
            try await license.fetch(to: context.payload.appendingPathComponent("LICENSE"), using: context.fetcher)
        }
        if kind == .rustfs {
            try await LZMALinker(context: context).bundleLibraryIfNeeded(
                for: context.payload.appendingPathComponent(binary))
        }
    }
}
