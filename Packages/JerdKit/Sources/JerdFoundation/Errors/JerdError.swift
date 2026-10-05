import Foundation

/// The single error type of Jerd: a machine-readable kind and a message that a user can act on.
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

    public let kind: Kind
    public let message: String

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
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
