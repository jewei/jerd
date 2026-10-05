import Foundation

/// The rules for runtime IDs, versions, and runtime paths saved in service settings.
public enum SafeIdentifier {
    /// 1 to 100 characters, not `.` or `..`, and only `0-9`, `A-Z`, `a-z`, `-`, and `.`.
    public static func isValid(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 100 && value != "." && value != ".."
            && value.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45
                    || byte == 46
            }
    }

    /// An absolute path without a control character.
    public static func isAbsolutePath(_ value: String) -> Bool {
        value.hasPrefix("/") && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
