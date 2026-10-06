import Foundation

/// Reads and replaces the hosts file. The helper uses `GuardedFileSwap`; tests use a temporary file.
public protocol HostsFileAccessing: Sendable {
    /// The current bytes. There is no lock.
    func read() throws -> Data
    /// Replaces the file only while it still holds `expected`, keeping its metadata.
    func replace(expected: Data, with replacement: Data) async throws
}
