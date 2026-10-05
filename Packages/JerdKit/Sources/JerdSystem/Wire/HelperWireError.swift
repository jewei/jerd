import Foundation
import JerdFoundation

/// Carries the kind of a helper error across XPC inside the error text.
///
/// The wire has only a text field for errors. The helper appends a stable code, for example
/// `The hosts file changed. (JERD-INVALID)`. An older app shows the text as it is, which stays
/// readable. A newer app reads the code, and maps a text without a code (from an older helper)
/// to `.unavailable`, as older apps did. The codes never change, also when a kind is renamed.
public enum HelperWireError {
    /// The stable code of each error kind.
    public static let codes: [JerdError.Kind: String] = [
        .invalid: "INVALID", .unavailable: "UNAVAILABLE", .corrupt: "CORRUPT", .locked: "LOCKED",
        .timedOut: "TIMED-OUT", .processFailed: "PROCESS", .approvalInterrupted: "APPROVAL-INTERRUPTED",
        .partialChange: "PARTIAL-CHANGE",
    ]

    private static let prefix = " (JERD-"

    /// The reply text for `error`. An error that is not a `JerdError` is sent as `.unavailable`.
    public static func text(for error: any Error) -> String {
        let jerd = error as? JerdError ?? JerdError.unavailable(error.localizedDescription)
        return "\(jerd.message)\(prefix)\(codes[jerd.kind] ?? "UNAVAILABLE"))"
    }

    /// The error that a reply text describes.
    public static func error(from text: String) -> JerdError {
        guard text.hasSuffix(")"), let marker = text.range(of: prefix, options: .backwards) else {
            return .unavailable(text)
        }
        let code = String(text[marker.upperBound..<text.index(before: text.endIndex)])
        let message = String(text[..<marker.lowerBound])
        guard !code.isEmpty, code.allSatisfy({ ("A"..."Z").contains($0) || $0 == "-" }) else {
            return .unavailable(text)
        }
        // A code from a newer helper that this app does not know keeps the safe default kind.
        guard let kind = codes.first(where: { $0.value == code })?.key else { return .unavailable(message) }
        return JerdError(kind, message)
    }
}
