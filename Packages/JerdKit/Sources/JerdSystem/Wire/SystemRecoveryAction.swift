/// The recovery that the user approved. The raw values are sent over XPC.
public enum SystemRecoveryAction: String, Codable, Sendable, CaseIterable {
    /// Put back the registration, hosts section, and trust from before the transaction.
    /// For a first setup, this removes the setup.
    case restorePrevious
    /// Remove the recorded hosts section, CA, and registration.
    case removeSetup
}
