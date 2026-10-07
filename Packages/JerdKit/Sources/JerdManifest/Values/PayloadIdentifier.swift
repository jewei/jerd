/// The one identifier rule for payload IDs and payload folder names.
///
/// An identifier has 1 to 100 characters `A-Z`, `a-z`, `0-9`, `.`, or `-`, starts with a letter
/// or digit, and so can never be `.`, `..`, or a path with a separator.
public enum PayloadIdentifier {
    /// The maximum length in characters.
    public static let maximumLength = 100

    /// True when `text` is a safe identifier.
    public static func isValid(_ text: String) -> Bool {
        guard let first = text.utf8.first, isLetterOrDigit(first), text.utf8.count <= maximumLength else {
            return false
        }
        return text.utf8.allSatisfy { isLetterOrDigit($0) || $0 == UInt8(ascii: ".") || $0 == UInt8(ascii: "-") }
    }

    private static func isLetterOrDigit(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
    }
}
