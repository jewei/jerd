@testable import JerdDevKit

/// The event lines that the test app writes in each case, as Sparkle produces them.
enum UpdateEvents {
    static let installed = ["pid:101", "launched:1", "found:2", "extracting", "ready"]
    static let relaunched = ["pid:202", "launched:2", "updated", "quit-deferred:2", "quit-approved:2"]
    static let success = installed + ["quit-deferred:1", "quit-approved:1"] + relaunched
    static let refusedQuit =
        installed + ["quit-deferred-refusal", "quit-refused", "version-after-refusal:1", "quit-deferred:1"]
        + ["quit-approved:1"] + relaunched
    static let noUpdate = ["pid:101", "launched:1", "no-update"]
    static let mismatch =
        "error:SUSparkleErrorDomain:3002:The update is improperly signed. EdDSA signature does not match"
    static let alteredFeed =
        ["pid:101", "launched:1", "error:SUSparkleErrorDomain:1000:The feed is invalid.", mismatch]
        + ["failed"]
    static let alteredArchive = ["pid:101", "launched:1", "found:2", "extracting", mismatch, "failed"]

    static func text(_ lines: [String]) -> String { lines.joined(separator: "\n") + "\n" }

    static func expected(for testCase: UpdateCase) -> (events: String, version: String) {
        switch testCase {
        case .noUpdate: (text(noUpdate), "1")
        case .alteredFeed: (text(alteredFeed), "1")
        case .alteredArchive: (text(alteredArchive), "1")
        case .success: (text(success), "2")
        case .refusedQuit: (text(refusedQuit), "2")
        }
    }
}
