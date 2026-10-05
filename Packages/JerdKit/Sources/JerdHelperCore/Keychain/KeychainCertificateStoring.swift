import Foundation

/// The CA items in the system keychain. The live type is `SystemKeychainCertificates`.
protocol KeychainCertificateStoring: Sendable {
    /// Adds the certificate. Returns whether this call added it or it was already present.
    func add(_ der: Data) throws -> KeychainAddOutcome
    /// Deletes the one keychain item whose bytes equal `der`. An absent item is not an error.
    func deleteExact(_ der: Data) throws
}
