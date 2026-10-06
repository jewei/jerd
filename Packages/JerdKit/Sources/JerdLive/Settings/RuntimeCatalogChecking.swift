import JerdManifest
import JerdRuntimes

/// Reads the publisher catalog of one kind. `RuntimeCatalog` is the live type.
package protocol RuntimeCatalogChecking: Sendable {
    func check(_ kind: RuntimeKind) async -> RuntimeUpdateCheck
}

extension RuntimeCatalog: RuntimeCatalogChecking {}
