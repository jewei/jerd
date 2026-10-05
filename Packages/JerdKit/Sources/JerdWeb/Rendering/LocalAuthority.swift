import Foundation

/// The Caddy certificate authority of a run: its storage ID and its certificate name.
///
/// This is the only place that names the CA. The installation CA (`jerd`) is the one the user
/// approves; preflight and tests use an isolated CA (`jerd-test`) that is never trusted.
public struct LocalAuthority: Equatable, Hashable, Sendable {
    /// The Caddy PKI ID and the folder name below `pki/authorities/`.
    public let id: String
    /// The `name` and `root_common_name` of the CA.
    public let name: String
    /// The installation that owns the CA. Nil for the isolated test CA.
    public let installationID: UUID?

    /// The CA of this installation: `jerd`, named `Jerd Local CA <UUID>` (uppercase UUID).
    public static func installation(_ installationID: UUID) -> LocalAuthority {
        LocalAuthority(
            id: "jerd", name: "Jerd Local CA \(installationID.uuidString)", installationID: installationID)
    }

    /// The isolated CA of preflight runs and tests.
    public static let isolatedTest = LocalAuthority(id: "jerd-test", name: "Jerd isolated test CA", installationID: nil)

    /// The PEM root certificate that Caddy writes below its storage folder.
    public func rootCertificate(in storage: URL) -> URL {
        storage.appendingPathComponent("pki", isDirectory: true)
            .appendingPathComponent("authorities", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("root.crt", isDirectory: false)
    }
}
