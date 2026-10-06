import Foundation

/// The dated JSON record that a manual harness writes in `.build/evidence`, for a pass and for a
/// failure. It replaces prose evidence: it says exactly what ran, where, on which commit, and how
/// each case ended.
struct EvidenceRecord: Codable, Equatable, Sendable {
    /// The result of one harness case.
    struct CaseResult: Codable, Equatable, Sendable {
        var name: String
        var passed: Bool
        var detail: String
    }

    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    /// `updates` or `xpc`.
    var check: String
    /// ISO 8601 in UTC, for example `2026-10-06T09:15:00Z`.
    var date: String
    var identity: String
    var facts: SystemFacts
    /// `passed` or `failed`.
    var result: String
    /// Why the harness stopped early. Absent when every case ran.
    var message: String?
    var cases: [CaseResult]

    var passed: Bool { result == "passed" }

    init(
        check: String, date: Date, identity: String, facts: SystemFacts, message: String?, cases: [CaseResult]
    ) {
        self.check = check
        self.date = Self.isoDate(date)
        self.identity = identity
        self.facts = facts
        self.message = message
        self.cases = cases
        result = message == nil && !cases.isEmpty && cases.allSatisfy(\.passed) ? "passed" : "failed"
    }

    /// Two-space indentation, sorted keys, and a final line break.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    /// `<UTC date and time>-<check>.json`, for example `2026-10-06T091500Z-updates.json`. The name has no
    /// colon, so it is a valid file name everywhere, and names sort by date.
    static func fileName(check: String, date: Date) -> String {
        "\(format(date, "yyyy-MM-dd'T'HHmmss'Z'"))-\(check).json"
    }

    static func isoDate(_ date: Date) -> String {
        format(date, "yyyy-MM-dd'T'HH:mm:ss'Z'")
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
