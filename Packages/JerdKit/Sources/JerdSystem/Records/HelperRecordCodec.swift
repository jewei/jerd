import Foundation
import JerdFoundation

/// Encodes and decodes the helper records with the exact encoder options of earlier helpers
/// (`JSONEncoder()` defaults). Every decoding failure becomes a `.corrupt` error that names the
/// record and the reason, never a raw `DecodingError`.
enum HelperRecordCodec {
    /// The two forms of `pending.json`.
    enum PendingForm: Equatable, Sendable {
        /// A version 1 journal.
        case journal(SetupJournal)
        /// A bare registration that a very old helper saved before a transaction.
        case legacy(RegistrationRecord)
    }

    static func encode(_ value: some Encodable) throws -> Data { try JSONEncoder().encode(value) }

    static func decodeRegistration(_ data: Data) throws -> RegistrationRecord {
        do {
            return try JSONDecoder().decode(RegistrationRecord.self, from: data)
        } catch let error as JerdError where error.kind == .corrupt {
            throw error
        } catch {
            throw JerdError.corrupt("The helper registration cannot be read. It was preserved. \(describe(error))")
        }
    }

    /// Tells a journal from a legacy record by its keys, then decodes it. No form is guessed after a failure.
    static func decodePending(_ data: Data) throws -> PendingForm {
        guard let object = try? JSONSerialization.jsonObject(with: data), let keys = (object as? [String: Any])?.keys
        else { throw JerdError.corrupt("The helper recovery record is not a JSON object. It was preserved.") }
        let journalKeys: Set<String> = ["operation", "phase", "hostsSHA256", "intended", "previousBytes"]
        if !journalKeys.isDisjoint(with: keys) { return .journal(try decodeJournal(data)) }
        guard keys.contains("ownerUID") else {
            throw JerdError.corrupt("The helper recovery record has an unknown form. It was preserved.")
        }
        do {
            return .legacy(try JSONDecoder().decode(RegistrationRecord.self, from: data))
        } catch {
            throw JerdError.corrupt(
                "The legacy helper recovery record is invalid. It was preserved. \(describe(error))")
        }
    }

    private static func decodeJournal(_ data: Data) throws -> SetupJournal {
        let journal: SetupJournal
        do {
            journal = try JSONDecoder().decode(SetupJournal.self, from: data)
        } catch {
            throw JerdError.corrupt("The helper recovery record is invalid. It was preserved. \(describe(error))")
        }
        guard journal.schemaVersion == SetupJournal.currentVersion,
            SetupOperation(rawValue: journal.operation) != nil, journal.intended ?? journal.previous != nil
        else { throw JerdError.corrupt("The helper recovery record is invalid. It was preserved.") }
        return journal
    }

    /// A short reason for a decoding failure, without the raw Foundation text.
    static func describe(_ error: any Error) -> String {
        switch error {
        case let error as JerdError:
            return error.message
        case DecodingError.keyNotFound(let key, _):
            return "The key \(key.stringValue) is missing."
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            return "The value of \(path(context)) has the wrong type."
        case DecodingError.dataCorrupted(let context):
            return context.codingPath.isEmpty ? "The JSON is malformed." : "The value of \(path(context)) is invalid."
        default:
            return error.localizedDescription
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }
}
