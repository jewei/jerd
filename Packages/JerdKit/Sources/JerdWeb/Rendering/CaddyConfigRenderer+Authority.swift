import Foundation

extension CaddyConfigRenderer {
    /// The PKI-only `prepare-ca.json`: `caddy validate` with it creates the CA and opens no listener.
    ///
    /// The file is compact with escaped slashes, as the old generator wrote it. Keys are sorted
    /// so the output is deterministic.
    public static func renderAuthorityPreparation(authority: LocalAuthority, storage: URL) throws -> Data {
        let document: JSONValue = [
            "admin": ["disabled": true],
            "storage": storageValue(storage),
            "apps": ["pki": pki(authority)],
        ]
        return try document.serialized([.sortedKeys])
    }
}
