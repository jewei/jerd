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
    /// The read includes room for two of the longest secret, and redaction happens before the cut.
    /// When the read starts inside the file, the first `room` bytes are dropped after redaction,
    /// because only they can hold the end of a secret that the read cut. So no fragment of a secret
    /// shows, even when redaction or multibyte text makes the text shorter. Returns `fallback` when
    /// the log is missing, empty, or unreadable.
    public func tail(redacting secrets: [String], fallback: String) -> String {
        let room = secrets.map(\.utf8.count).max() ?? 0
        let limit = Self.tailLimit + 2 * room
        guard let raw = try? file.readTail(limit: limit), !raw.isEmpty else { return fallback }
        let redacted = LogRedactor.redact(raw, values: secrets)
        let whole = raw.utf8.count < limit
        let safe = whole ? Substring(redacted) : Self.dropping(leadingBytes: room, of: redacted)
        return String(safe.suffix(Self.tailLimit))
    }

    /// `text` without its first characters that together have at least `count` UTF-8 bytes.
    private static func dropping(leadingBytes count: Int, of text: String) -> Substring {
        var index = text.startIndex
        var dropped = 0
        while dropped < count, index < text.endIndex {
            dropped += text[index].utf8.count
            index = text.index(after: index)
        }
        return text[index...]
    }
}
