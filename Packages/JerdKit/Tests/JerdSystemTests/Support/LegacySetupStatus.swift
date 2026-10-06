import Foundation

@testable import JerdSystem

/// A copy of the old app's `SystemSetupStatus` declaration (JerdCore, before the rewrite), to prove
/// that an old app can still decode what the new helper sends.
struct LegacySetupStatus: Codable {
    var hostnames: [String]
    var installationID: UUID?
    var certificateSHA256: String?
    var certificateDER: Data?
    var hostsConfigured: Bool
    var trustConfigured: Bool
    var trustPolicy: CertificateTrustPolicy
    var recovery: LegacyRecoveryStatus?
}

/// A copy of the old `SystemRecoveryStatus`: `installationID` and `certificateDER` are required.
struct LegacyRecoveryStatus: Codable {
    let id: String
    let operation: String
    let phase: String
    let details: [String]
    let canRestore: Bool
    let canRemove: Bool
    let installationID: UUID
    let certificateDER: Data
    let previousHostnames: [String]
    let intendedHostnames: [String]
    let policies: [CertificateTrustPolicy]
}
