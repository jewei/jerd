import Foundation
import JerdFoundation

/// The helper's report of an interrupted transaction, and the recovery actions it allows.
///
/// JSON keys: `id`, `operation`, `phase`, `details`, `canRestore`, `canRemove`, `installationID`,
/// `certificateDER`, `previousHostnames`, `intendedHostnames`, `policies`. `installationID` and
/// `certificateDER` are nil only when the recovery record cannot be read; then no action is allowed.
/// On the wire they are always present (see `SystemRecoveryStatus+Codable.swift`).
public struct SystemRecoveryStatus: Codable, Equatable, Identifiable, Sendable {
    /// The lowercase SHA-256 of the `pending.json` bytes. An approval must name it.
    public let id: String
    public let operation: String
    public let phase: String
    public let details: [String]
    public let canRestore: Bool
    public let canRemove: Bool
    public let installationID: UUID?
    public let certificateDER: Data?
    public let previousHostnames: [String]
    public let intendedHostnames: [String]
    /// The trust policies that a recovery can apply, in `CertificateTrustPolicy` order.
    public let policies: [CertificateTrustPolicy]

    public init(
        id: String, operation: String, phase: String, details: [String], canRestore: Bool, canRemove: Bool,
        installationID: UUID?, certificateDER: Data?, previousHostnames: [String], intendedHostnames: [String],
        policies: [CertificateTrustPolicy]
    ) {
        self.id = id
        self.operation = operation
        self.phase = phase
        self.details = details
        self.canRestore = canRestore
        self.canRemove = canRemove
        self.installationID = installationID
        self.certificateDER = certificateDER
        self.previousHostnames = previousHostnames
        self.intendedHostnames = intendedHostnames
        self.policies = policies
    }

    /// The lowercase SHA-256 of the recorded CA, or nil when the record cannot be read.
    public var fingerprint: String? { certificateDER.map { FileDigest.hexSHA256(of: $0) } }
}
