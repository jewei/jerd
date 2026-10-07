import Darwin

/// The saved identity of a running service process: `active-run.json` or `processes/<UUID>.json`.
///
/// The JSON keys are a compatibility contract. Accepted forms:
/// - full: `identity`, `controller`, `gracefulSignal` (and `descendants` after a recovery attempt);
/// - fallback: no `identity` (the capture failed), still `controller` and `gracefulSignal`;
/// - legacy: only `processID` and `runtimeID`.
/// Records without `identity` or `controller` are never signalled.
public struct ActiveRunRecord: Codable, Equatable, Sendable {
    /// The largest record, on read and on write.
    public static let maximumBytes = 131_072
    /// The most descendants one record can list.
    public static let maximumDescendants = 1_024

    /// The group leader PID. It must be greater than 1.
    public let processID: Int32
    /// Free text: a runtime ID for services, a label such as "PHP 8.4.0" for web processes.
    public let runtimeID: String
    public let identity: ProcessIdentity?
    /// The Jerd process that started the service.
    public let controller: ProcessIdentity?
    /// The graceful stop signal: 15 SIGTERM, 2 SIGINT (PostgreSQL), or 3 SIGQUIT (PHP-FPM).
    public let gracefulSignal: Int32?
    /// Verified group members, written only by recovery before it signals.
    public var descendants: [ProcessIdentity]?

    public init(
        processID: Int32, runtimeID: String, identity: ProcessIdentity?, controller: ProcessIdentity?,
        gracefulSignal: Int32?, descendants: [ProcessIdentity]? = nil
    ) {
        self.processID = processID
        self.runtimeID = runtimeID
        self.identity = identity
        self.controller = controller
        self.gracefulSignal = gracefulSignal
        self.descendants = descendants
    }

    /// The signal for a graceful stop. A record without one uses SIGTERM.
    public var signal: Int32 { gracefulSignal ?? SIGTERM }

    /// True when the record passes the structural rules: PID above 1, a matching identity PID,
    /// and at most 1 024 descendants.
    public var isWellFormed: Bool {
        processID > 1 && (identity.map { $0.processID == processID } ?? true)
            && (descendants?.count ?? 0) <= Self.maximumDescendants
    }
}
