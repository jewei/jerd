import Foundation

/// The single error type of Jerd: a machine-readable kind, a message that a user can act on, and,
/// for a few failures, the remedy that a page can offer as a button.
public struct JerdError: Error, LocalizedError, Equatable, Hashable, Sendable {
    /// The category of a failure. Callers branch on the kind, never on the message text.
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// The input or a requested change breaks a rule.
        case invalid
        /// A resource or capability is not available now.
        case unavailable
        /// Saved data cannot be read or has an unexpected form. The data is preserved.
        case corrupt
        /// Another owner holds an exclusive lock.
        case locked
        /// An operation did not finish before its deadline.
        case timedOut
        /// A process could not be started, inspected, or stopped.
        case processFailed
        /// The user or the system interrupted an approval.
        case approvalInterrupted
        /// Only part of a multi-step change was applied.
        case partialChange
    }

    /// A step that fixes the failure and that a page can offer as a button. The message names the
    /// same step, so a page without the button still tells the user what to do.
    public enum Remedy: String, Sendable, Hashable, CaseIterable {
        /// Register the privileged helper again (Reconnect Helper…).
        case reconnectHelper
        /// Open System Settings → General → Login Items & Extensions.
        case openLoginItems
    }

    public let kind: Kind
    public let message: String
    public private(set) var remedy: Remedy?

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }

    /// The same error with `remedy`.
    public func with(_ remedy: Remedy) -> JerdError {
        var copy = self
        copy.remedy = remedy
        return copy
    }

    public var errorDescription: String? { message }

    public static func invalid(_ message: String) -> Self { Self(.invalid, message) }
    public static func unavailable(_ message: String) -> Self { Self(.unavailable, message) }
    public static func corrupt(_ message: String) -> Self { Self(.corrupt, message) }
    public static func locked(_ message: String) -> Self { Self(.locked, message) }
    public static func timedOut(_ message: String) -> Self { Self(.timedOut, message) }
    public static func processFailed(_ message: String) -> Self { Self(.processFailed, message) }
    public static func approvalInterrupted(_ message: String) -> Self { Self(.approvalInterrupted, message) }
    public static func partialChange(_ message: String) -> Self { Self(.partialChange, message) }
}
