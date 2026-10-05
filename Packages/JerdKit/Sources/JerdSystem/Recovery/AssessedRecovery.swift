import Foundation

/// An assessment and the hosts bytes it was made from.
struct AssessedRecovery: Sendable {
    let assessment: RecoveryAssessor.Assessment
    let currentHosts: Data

    var status: SystemRecoveryStatus { assessment.status }

    func hosts(for action: SystemRecoveryAction) -> Data? { assessment.hosts(for: action) }
}
