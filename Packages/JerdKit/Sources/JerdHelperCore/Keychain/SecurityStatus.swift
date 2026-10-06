import Foundation
import JerdFoundation
import Security

/// Turns a Security status into a user message.
enum SecurityStatus {
    /// The system text of `status`, or "OSStatus <n>".
    static func describe(_ status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
    }

    /// Throws `.unavailable("Cannot <operation>: <text>")` unless `status` is success.
    static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == errSecSuccess else { throw JerdError.unavailable("Cannot \(operation): \(describe(status))") }
    }
}
