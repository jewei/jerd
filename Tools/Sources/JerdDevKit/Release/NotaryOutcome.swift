import Foundation

/// The JSON result of `notarytool submit --wait --output-format json`.
///
/// It is read from standard output only. Progress and warnings go to standard error and can never
/// break the parse. `notarytool` exits with a non-zero status for an `Invalid`
/// result, so the caller parses standard output before it looks at the status.
struct NotaryOutcome: Codable, Equatable, Sendable {
    var id: String?
    var status: String?
    var message: String?

    var isAccepted: Bool { status == "Accepted" }

    /// The outcome, or nil when standard output holds no JSON object.
    static func parse(standardOutput: String) -> NotaryOutcome? {
        let text = standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("{"), let outcome = try? JSONDecoder().decode(Self.self, from: Data(text.utf8)) else {
            return nil
        }
        return outcome
    }

    /// A submission ID is a UUID; it is used as an argument of `notarytool log`.
    var validID: String? {
        guard let id, UUID(uuidString: id) != nil else { return nil }
        return id
    }
}
