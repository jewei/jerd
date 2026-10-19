import Foundation

/// The Caddy certificate authority of a run: its storage ID and its certificate name.
///
/// This is the only place that names the CA. The installation CA is the one the user approves:
/// `jerd-2`, which Jerd makes with name constraints, or `jerd`, which Caddy made for earlier
/// builds (`ActiveAuthority` chooses). Preflight and tests use an isolated CA (`jerd-test`) that is
/// never trusted.
public struct LocalAuthority: Equatable, Hashable, Sendable {
    /// The Caddy PKI ID and the folder name below `pki/authorities/`.
    public let id: String
    /// The `name` and `root_common_name` of the CA.
    public let name: String
    /// The installation that owns the CA. Nil for the isolated test CA.
    public let installationID: UUID?

    /// The CA that Caddy made for this installation: `jerd`, named `Jerd Local CA <UUID>`
    /// (uppercase UUID).
    public static func installation(_ installationID: UUID) -> LocalAuthority {
        LocalAuthority(
            id: "jerd", name: "Jerd Local CA \(installationID.uuidString)", installationID: installationID)
    }

    /// The CA that Jerd makes for this installation: `jerd-2`, with the same name, so that the
    /// helper and earlier builds recognize it.
    public static func constrainedInstallation(_ installationID: UUID) -> LocalAuthority {
        LocalAuthority(
            id: "jerd-2", name: "Jerd Local CA \(installationID.uuidString)", installationID: installationID)
    }

    /// True when Jerd writes the root and its key, so that Caddy loads them and makes only the
    /// intermediate.
    public var providesRoot: Bool { id == "jerd-2" }

    /// The isolated CA of preflight runs and tests.
    public static let isolatedTest = LocalAuthority(id: "jerd-test", name: "Jerd isolated test CA", installationID: nil)

    /// The PEM root certificate below the storage folder.
    public func rootCertificate(in storage: URL) -> URL {
        folder(in: storage).appendingPathComponent("root.crt", isDirectory: false)
    }

    /// The PEM private key of the root below the storage folder.
    public func rootKey(in storage: URL) -> URL {
        folder(in: storage).appendingPathComponent("root.key", isDirectory: false)
    }

    private func folder(in storage: URL) -> URL {
        storage.appendingPathComponent("pki", isDirectory: true)
            .appendingPathComponent("authorities", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }
}
