import Foundation

/// A prepared HTTPS setup that waits for the user: what the approval sheet shows. The live port
/// keeps the waiting change under `id` until `approve` or `discard`.
public struct HTTPSApproval: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// Every registered hostname. An approval covers enabled and disabled sites.
    public let hostnames: [String]
    /// Approved hostnames that this change removes from the setup.
    public let removedHostnames: [String]
    /// The SHA-256 of the local CA, which the user can compare in the macOS prompt.
    public let fingerprint: String

    public init(id: UUID = UUID(), hostnames: [String], removedHostnames: [String] = [], fingerprint: String) {
        self.id = id
        self.hostnames = hostnames
        self.removedHostnames = removedHostnames
        self.fingerprint = fingerprint
    }

    /// The sheet title, for example "Enable HTTPS for 3 hostnames?". It counts hostnames, not the
    /// sites that start, because the approval also covers disabled and stopped sites.
    public var title: String {
        hostnames.count == 1 ? "Enable HTTPS for \(hostnames[0])?" : "Enable HTTPS for \(hostnames.count) hostnames?"
    }
}
