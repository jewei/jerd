import Foundation
import JerdProcess

/// The server log of one instance (`server.log`) and its copy from the previous run.
public struct ServiceLog: Hashable, Sendable {
    /// The size of a log tail in a message.
    public static let tailLimit = 4_096

    public let file: ProcessLogFile
    public let previousFile: URL

    public init(file: URL, previousFile: URL) {
        self.file = ProcessLogFile(url: file)
        self.previousFile = previousFile
    }

    /// Trims the current log and keeps it as the previous log, so a new run starts empty but the
    /// output of a crashed run survives one restart.
    public func rotate() throws {
        try file.rotate(to: previousFile)
    }

    /// The last 4 096 characters of the log with every secret replaced by `[redacted]`.
    ///
    /// The read includes room for the longest secret, and redaction happens before the cut, so a
    /// secret that crosses the cut cannot leave a fragment. Returns `fallback` when the log is
    /// missing, empty, or unreadable.
    public func tail(redacting secrets: [String], fallback: String) -> String {
        let room = secrets.map(\.utf8.count).max() ?? 0
        guard let raw = try? file.readTail(limit: Self.tailLimit + room), !raw.isEmpty else { return fallback }
        let redacted = LogRedactor.redact(raw, values: secrets)
        return String(redacted.suffix(Self.tailLimit))
    }
}
