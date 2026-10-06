/// The recovery payload. JSON keys: `recordID` (the `SystemRecoveryStatus.id`) and `action`.
public struct SystemRecoveryApproval: Codable, Equatable, Sendable {
    public let recordID: String
    public let action: SystemRecoveryAction

    public init(recordID: String, action: SystemRecoveryAction) {
        self.recordID = recordID
        self.action = action
    }
}
