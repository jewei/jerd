import Foundation

/// A registered PHP runtime as the Runtimes page shows it.
public struct RegisteredPHP: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let version: String
    /// The archive digest of the managed build that supplies this runtime, if any.
    public let buildDigest: String?

    public init(id: UUID, version: String, buildDigest: String? = nil) {
        self.id = id
        self.version = version
        self.buildDigest = buildDigest
    }
}
