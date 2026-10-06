import Foundation

/// The journal of an unfinished transaction, saved as `pending.json` (version 1).
///
/// Keys: `schemaVersion` (required, 1), `operation`, `previous?`, `previousBytes?` (the exact bytes of
/// the earlier `registration.json`; present exactly when `previous` is), `intended?` (absent for a
/// removal), `hostsSHA256` (of the hosts bytes before the transaction), and `phase` (free text).
struct SetupJournal: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var schemaVersion = Self.currentVersion
    let operation: String
    let previous: RegistrationRecord?
    let previousBytes: Data?
    let intended: RegistrationRecord?
    let hostsSHA256: String
    var phase: String

    init(
        operation: SetupOperation, previous: RegistrationRecord?, previousBytes: Data?, intended: RegistrationRecord?,
        hostsSHA256: String, phase: String
    ) {
        self.operation = operation.rawValue
        self.previous = previous
        self.previousBytes = previousBytes
        self.intended = intended
        self.hostsSHA256 = hostsSHA256
        self.phase = phase
    }

    /// Equal except for the phase: the same transaction at another step.
    func isSameTransaction(as other: SetupJournal) -> Bool {
        var copy = other
        copy.phase = phase
        return copy == self
    }
}
