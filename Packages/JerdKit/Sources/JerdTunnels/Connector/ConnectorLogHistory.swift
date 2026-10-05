import Foundation
import JerdFoundation
import JerdProcess

/// Keeps the output of earlier connector runs when a new run starts.
///
/// The process supervisor empties `server.log` at each launch. Earlier builds lost the output of a
/// crashed connector at the automatic restart (spec E 7.1.4). Before each launch, this type appends
/// the current log to `server.previous.log` (bounded to 4 MiB) and marks the boundary.
package struct ConnectorLogHistory: Sendable {
    /// The most bytes that the history file keeps.
    package static let retainedBytes = ProcessLogFile.defaultThreshold / 2
    /// The line after each archived run.
    package static let boundary = "[Jerd started a new connector.]\n"

    package let current: ProcessLogFile
    package let previous: ProcessLogFile

    package init(instance: TunnelInstanceLayout) {
        current = ProcessLogFile(url: instance.logFile)
        previous = ProcessLogFile(url: instance.previousLogFile)
    }

    /// Moves the output of the last run to the history and leaves an empty current log.
    package func archiveCurrent() throws {
        let latest = try current.readTail(limit: Self.retainedBytes)
        guard !latest.isEmpty else { return }
        var text = try previous.readTail(limit: Self.retainedBytes) + latest
        if !text.hasSuffix("\n") { text += "\n" }
        text += Self.boundary
        try AtomicFile.write(Data(text.utf8).suffix(Self.retainedBytes), to: previous.url, durability: .standard)
        try AtomicFile.write(Data(), to: current.url, durability: .standard)
    }

    /// The last `limit` bytes of the history and the current run, or nil when neither file exists.
    package func recent(limit: Int) throws -> String? {
        let present = [current.url, previous.url].contains { FileProbe.presence(at: $0).mayExist }
        guard present else { return nil }
        let text = try previous.readTail(limit: limit) + current.readTail(limit: limit)
        return String(decoding: Data(text.utf8).suffix(limit), as: UTF8.self)
    }
}
