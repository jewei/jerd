/// Reads the hosts file text for the conflict check. Tests use a fixed text.
public protocol HostsFileReading: Sendable {
    /// The whole text of the hosts file.
    func read() throws -> String
}
