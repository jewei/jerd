/// The registration state of the helper daemon, as `SMAppService` reports it.
public enum HelperAvailability: String, Sendable, CaseIterable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}
