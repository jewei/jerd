import Foundation
import JerdFoundation
import Testing

@testable import JerdSystem

/// `Fixtures/Records` holds JSON that the old helper wrote (v3 and journals) and the v1 and v2 forms.
@Suite struct HelperRecordCodecTests {
    private func registration(_ name: String) throws -> RegistrationRecord {
        try HelperRecordCodec.decodeRegistration(Fixture.data("Records/\(name).json"))
    }

    private func object(_ data: Data) throws -> NSDictionary {
        try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test func readsVersionOneAsASingleHostnameWithTheHostnamePolicy() throws {
        let record = try registration("registration-v1")
        #expect(record.hostnames.strings == ["shop.test"])
        #expect(record.trustPolicy == .hostnames)
        #expect(record.ownerUID == 501 && record.installationID == Fixture.installationID)
    }

    @Test func readsVersionTwoSortedWithTheHostnamePolicy() throws {
        let record = try registration("registration-v2")
        #expect(record.hostnames.strings == ["blog.test", "shop.test"])
        #expect(record.trustPolicy == .hostnames)
    }

    @Test func writesVersionThreeExactlyAsTheOldHelper() throws {
        let golden = try Fixture.data("Records/registration-v3.json")
        let record = try HelperRecordCodec.decodeRegistration(golden)
        #expect(record.trustPolicy == .serverTLS)
        #expect(try object(HelperRecordCodec.encode(record)) == object(golden))
    }

    @Test func versionIsIgnoredByEquality() throws {
        let upgraded = try HelperRecordCodec.decodeRegistration(
            HelperRecordCodec.encode(registration("registration-v2")))
        #expect(upgraded == (try registration("registration-v2")))
    }

    @Test(arguments: [0, 4, 99])
    func refusesAnUnsupportedVersion(version: Int) throws {
        let text = String(decoding: try Fixture.data("Records/registration-v3.json"), as: UTF8.self)
            .replacingOccurrences(of: "\"schemaVersion\":3", with: "\"schemaVersion\":\(version)")
        #expect(throws: JerdError.corrupt("The helper registration version is unsupported.")) {
            try HelperRecordCodec.decodeRegistration(Data(text.utf8))
        }
    }

    @Test(arguments: [
        (#"{"schemaVersion":3}"#, "The key ownerUID is missing."),
        ("not json", "The JSON is malformed."),
        (#"{"schemaVersion":"3"}"#, "The value of schemaVersion has the wrong type."),
    ])
    func namesTheReasonOfACorruptRegistration(json: String, reason: String) {
        #expect(throws: JerdError.corrupt("The helper registration cannot be read. It was preserved. \(reason)")) {
            try HelperRecordCodec.decodeRegistration(Data(json.utf8))
        }
    }

    @Test(arguments: ["pending-configure", "pending-configure-new", "pending-remove"])
    func readsAndWritesTheOldJournals(name: String) throws {
        let golden = try Fixture.data("Records/\(name).json")
        guard case .journal(let journal) = try HelperRecordCodec.decodePending(golden) else {
            Issue.record("Expected a journal")
            return
        }
        #expect(try object(HelperRecordCodec.encode(journal)) == object(golden))
    }

    @Test func readsALegacyPendingRecord() throws {
        guard
            case .legacy(let record) = try HelperRecordCodec.decodePending(Fixture.data("Records/pending-legacy.json"))
        else {
            Issue.record("Expected a legacy record")
            return
        }
        #expect(record.hostnames.strings == ["shop.test"])
    }

    /// Fixed problem 14: a journal with one bad field gives a specific message, not a legacy guess.
    @Test(arguments: [
        (
            #"{"schemaVersion":1,"operation":"Configure HTTPS","phase":"x"}"#,
            "The helper recovery record is invalid. It was preserved. The key hostsSHA256 is missing."
        ),
        (
            #"{"schemaVersion":2,"operation":"Configure HTTPS","phase":"x","hostsSHA256":"a"}"#,
            "The helper recovery record is invalid. It was preserved."
        ),
        (
            #"{"schemaVersion":1,"operation":"Other","phase":"x","hostsSHA256":"a"}"#,
            "The helper recovery record is invalid. It was preserved."
        ),
        (
            #"{"schemaVersion":1,"operation":"Remove HTTPS","phase":"x","hostsSHA256":"a"}"#,
            "The helper recovery record is invalid. It was preserved."
        ),
        ("[1]", "The helper recovery record is not a JSON object. It was preserved."),
        ("{", "The helper recovery record is not a JSON object. It was preserved."),
        (#"{"unrelated":true}"#, "The helper recovery record has an unknown form. It was preserved."),
        (
            #"{"ownerUID":501,"schemaVersion":1}"#,
            "The legacy helper recovery record is invalid. It was preserved. The key installationID is missing."
        ),
    ])
    func everyCorruptPendingFormHasASpecificMessage(json: String, message: String) {
        #expect(throws: JerdError.corrupt(message)) { try HelperRecordCodec.decodePending(Data(json.utf8)) }
    }

    @Test func journalsOfOneTransactionDifferOnlyInPhase() throws {
        guard
            case .journal(let journal) = try HelperRecordCodec.decodePending(
                Fixture.data("Records/pending-configure.json"))
        else { return }
        var later = journal
        later.phase = "Approved recovery started; inspect current state before retrying"
        #expect(journal.isSameTransaction(as: later))
        guard
            case .journal(let other) = try HelperRecordCodec.decodePending(Fixture.data("Records/pending-remove.json"))
        else { return }
        #expect(!journal.isSameTransaction(as: other))
    }
}
