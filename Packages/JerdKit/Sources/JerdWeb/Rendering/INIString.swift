import JerdFoundation

/// Quoting of path values in PHP INI and PHP-FPM files.
public enum INIString {
    /// `"value"` with `\` and `"` escaped.
    ///
    /// PHP expands `${NAME}` inside INI strings, and a control character can end the line, so a
    /// value with either is refused instead of escaped.
    public static func quote(_ value: String) throws -> String {
        guard !value.contains("${"), !value.unicodeScalars.contains(where: { $0.value < 32 }) else {
            throw JerdError.invalid(
                "Configuration paths cannot contain control characters or environment substitutions.")
        }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
