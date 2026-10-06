import Darwin
import Foundation
import JerdFoundation

/// A validated `pending.json`: the journal (or a legacy record) and the setups before and after.
struct PendingRecord: Sendable {
    let bytes: Data
    let journal: SetupJournal?
    /// The setup whose CA the transaction uses: `intended`, or `previous` for a removal.
    let reference: RegistrationRecord
    let previous: RegistrationRecord?
    let intended: RegistrationRecord?

    /// The record ID that an approval must name: the SHA-256 of the exact bytes.
    var id: String { CertificateIdentity.sha256Hex(bytes) }

    /// Validates a decoded pending form for `owner`.
    ///
    /// - Parameter current: the committed registration, read only for a legacy record.
    static func validate(
        _ form: HelperRecordCodec.PendingForm, bytes: Data, owner: uid_t, current: () throws -> RegistrationRecord?
    ) throws -> PendingRecord {
        switch form {
        case .journal(let journal):
            return try validate(journal, bytes: bytes, owner: owner)
        case .legacy(let legacy):
            try requireOwnedCertificate(legacy, owner: owner)
            let committed = try current()
            if let committed, !committed.hasSameCertificate(as: legacy) {
                throw JerdError.corrupt(
                    "The legacy recovery record differs from the registration. Inspect both records manually.")
            }
            return PendingRecord(bytes: bytes, journal: nil, reference: legacy, previous: committed, intended: legacy)
        }
    }

    private static func validate(_ journal: SetupJournal, bytes: Data, owner: uid_t) throws -> PendingRecord {
        guard let reference = journal.intended ?? journal.previous else {
            throw JerdError.corrupt("The helper recovery record is invalid. It was preserved.")
        }
        try requireOwnedCertificate(reference, owner: owner)
        for record in [journal.previous, journal.intended].compactMap({ $0 }) {
            try requireOwnedCertificate(record, owner: owner)
            guard record.hasSameCertificate(as: reference) else {
                throw JerdError.corrupt("The recovery certificates do not match. Inspect the records manually.")
            }
        }
        try requireExactPreviousBytes(journal)
        return PendingRecord(
            bytes: bytes, journal: journal, reference: reference, previous: journal.previous, intended: journal.intended
        )
    }

    private static func requireExactPreviousBytes(_ journal: SetupJournal) throws {
        guard let previous = journal.previous else {
            guard journal.previousBytes == nil else {
                throw JerdError.corrupt("The previous registration is invalid.")
            }
            return
        }
        let mismatch = JerdError.corrupt("The previous registration does not match the recovery record.")
        guard let bytes = journal.previousBytes else { throw mismatch }
        let decoded: RegistrationRecord
        do { decoded = try HelperRecordCodec.decodeRegistration(bytes) } catch { throw mismatch }
        guard decoded == previous else { throw mismatch }
    }

    private static func requireOwnedCertificate(_ record: RegistrationRecord, owner: uid_t) throws {
        guard OwnerPolicy.isEligible(owner), record.ownerUID == owner else {
            throw JerdError.unavailable("This recovery record belongs to another user.")
        }
        _ = try record.trust()
    }
}
