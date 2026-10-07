import JerdFoundation
import JerdManifest
import JerdRuntimes

/// The pinned releases that the app installs on demand. `OnDemandRuntimes` is the live type; it
/// reads the catalog in the app bundle and never touches the network.
package protocol OnDemandRuntimeProviding: Sendable {
    func releases() throws -> [RuntimeRelease]
    /// A verified payload of the pin of `kind` that an earlier copy installed, for reuse.
    func reusablePayload(for kind: RuntimeKind, layout: DataLayout) async throws -> ReusablePayload?
}

extension OnDemandRuntimes: OnDemandRuntimeProviding {}
