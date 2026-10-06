import Foundation

/// Old apps require `installationID` and `certificateDER` (fixed review L4). A missing value goes on
/// the wire as a placeholder that an old app decodes and shows with both actions disabled: the nil
/// UUID and empty certificate bytes. Both placeholders, and a missing key, decode as nil again.
extension SystemRecoveryStatus {
    static let placeholderInstallationID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    private enum CodingKeys: String, CodingKey {
        case id, operation, phase, details, canRestore, canRemove, installationID, certificateDER
        case previousHostnames, intendedHostnames, policies
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let installationID = try container.decodeIfPresent(UUID.self, forKey: .installationID)
        let certificateDER = try container.decodeIfPresent(Data.self, forKey: .certificateDER)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            operation: try container.decode(String.self, forKey: .operation),
            phase: try container.decode(String.self, forKey: .phase),
            details: try container.decode([String].self, forKey: .details),
            canRestore: try container.decode(Bool.self, forKey: .canRestore),
            canRemove: try container.decode(Bool.self, forKey: .canRemove),
            installationID: installationID == Self.placeholderInstallationID ? nil : installationID,
            certificateDER: certificateDER?.isEmpty == true ? nil : certificateDER,
            previousHostnames: try container.decode([String].self, forKey: .previousHostnames),
            intendedHostnames: try container.decode([String].self, forKey: .intendedHostnames),
            policies: try container.decode([CertificateTrustPolicy].self, forKey: .policies))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(operation, forKey: .operation)
        try container.encode(phase, forKey: .phase)
        try container.encode(details, forKey: .details)
        try container.encode(canRestore, forKey: .canRestore)
        try container.encode(canRemove, forKey: .canRemove)
        try container.encode(installationID ?? Self.placeholderInstallationID, forKey: .installationID)
        try container.encode(certificateDER ?? Data(), forKey: .certificateDER)
        try container.encode(previousHostnames, forKey: .previousHostnames)
        try container.encode(intendedHostnames, forKey: .intendedHostnames)
        try container.encode(policies, forKey: .policies)
    }
}
