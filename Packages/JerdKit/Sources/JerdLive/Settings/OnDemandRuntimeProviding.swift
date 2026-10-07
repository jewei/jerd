import JerdRuntimes

/// The pinned releases that the app installs on demand. `OnDemandRuntimes` is the live type; it
/// reads the catalog in the app bundle and never touches the network.
package protocol OnDemandRuntimeProviding: Sendable {
    func releases() throws -> [RuntimeRelease]
}

extension OnDemandRuntimes: OnDemandRuntimeProviding {}
