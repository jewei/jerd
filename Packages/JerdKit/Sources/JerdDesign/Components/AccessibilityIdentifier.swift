/// Builds the stable accessibility identifiers that UI tests use, so tests do not find controls
/// by their visible text. An identifier is lower-case parts joined by dots, for example
/// `copy.inbox-url` or `site-editor.cancel`.
public enum AccessibilityIdentifier {
    /// Joins parts with dots. Each part becomes a slug; empty parts are left out.
    public static func make(_ parts: String...) -> String {
        parts.map(slug).filter { !$0.isEmpty }.joined(separator: ".")
    }

    /// Lower-case letters and digits; every other run of characters becomes one hyphen.
    /// For example "Inbox URL" becomes `inbox-url`.
    public static func slug(_ text: String) -> String {
        var result = ""
        var pendingHyphen = false
        for character in text.lowercased() {
            if character.isASCII && (character.isLetter || character.isNumber) {
                if pendingHyphen && !result.isEmpty { result.append("-") }
                result.append(character)
                pendingHyphen = false
            } else {
                pendingHyphen = true
            }
        }
        return result
    }
}
