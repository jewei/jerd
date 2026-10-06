import Foundation
import Testing

@testable import JerdDevKit

@Suite("Evidence record")
struct EvidenceRecordTests {
    static let facts = SystemFacts(
        macOSVersion: "27.0", xcodeVersion: "Xcode 27.0 Build version 27A100",
        commit: String(repeating: "a", count: 40),
        dirty: false)

    @Test("Encodes the golden format: sorted keys, UTC date, cases, and no message after a full run")
    func encodesGoldenFormat() throws {
        let record = EvidenceRecord(
            check: "updates", date: FakeHarnessClock.start, identity: "Developer ID Application: Test (ABCDE12345)",
            facts: Self.facts, message: nil,
            cases: [.init(name: "no-update", passed: true, detail: "passed")])
        let golden = """
            {
              "cases" : [
                {
                  "detail" : "passed",
                  "name" : "no-update",
                  "passed" : true
                }
              ],
              "check" : "updates",
              "date" : "2026-10-06T09:15:00Z",
              "facts" : {
                "commit" : "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "dirty" : false,
                "macOSVersion" : "27.0",
                "xcodeVersion" : "Xcode 27.0 Build version 27A100"
              },
              "identity" : "Developer ID Application: Test (ABCDE12345)",
              "result" : "passed",
              "schemaVersion" : 1
            }

            """
        #expect(String(decoding: try record.encoded(), as: UTF8.self) == golden)
    }

    @Test("A stop, a failed case, or no case at all makes the record failed")
    func failedResults() {
        let passed = EvidenceRecord.CaseResult(name: "a", passed: true, detail: "passed")
        let failed = EvidenceRecord.CaseResult(name: "b", passed: false, detail: "broken")
        func result(_ message: String?, _ cases: [EvidenceRecord.CaseResult]) -> String {
            EvidenceRecord(check: "x", date: .now, identity: "i", facts: Self.facts, message: message, cases: cases)
                .result
        }
        #expect(result(nil, [passed]) == "passed")
        #expect(result("stopped", [passed]) == "failed")
        #expect(result(nil, [passed, failed]) == "failed")
        #expect(result(nil, []) == "failed")
    }

    @Test("The file name sorts by UTC date and has no colon")
    func fileName() {
        #expect(EvidenceRecord.fileName(check: "xpc", date: FakeHarnessClock.start) == "2026-10-06T091500Z-xpc.json")
    }

    @Test("The record decodes again with the same values")
    func roundTrip() throws {
        let record = EvidenceRecord(
            check: "xpc", date: FakeHarnessClock.start, identity: "i", facts: Self.facts, message: "No test ran.",
            cases: [])
        #expect(try JSONDecoder().decode(EvidenceRecord.self, from: record.encoded()) == record)
    }
}
