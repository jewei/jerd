import Darwin

/// The parsed field output of `lsof -F`: process IDs (`p` lines) and socket names (`n` lines).
public struct ListenerReport: Equatable, Sendable {
    /// Every PID that `lsof` listed.
    public let processIDs: Set<pid_t>
    /// Every socket name, for example `127.0.0.1:3306`, `*:3306`, or `[::1]:3306`.
    public let addresses: Set<String>

    public init(processIDs: Set<pid_t>, addresses: Set<String>) {
        self.processIDs = processIDs
        self.addresses = addresses
    }

    /// Parses `lsof -F` output. Other field lines (for example `f` descriptors) are ignored.
    /// A `p` line that is not a positive integer makes the whole report unknown (nil).
    public static func parse(_ output: String) -> ListenerReport? {
        var processIDs: Set<pid_t> = []
        var addresses: Set<String> = []
        for line in output.split(whereSeparator: \.isNewline) {
            switch line.first {
            case "p":
                guard let pid = pid_t(line.dropFirst()), pid > 0 else { return nil }
                processIDs.insert(pid)
            case "n":
                addresses.insert(String(line.dropFirst()))
            default:
                continue
            }
        }
        return ListenerReport(processIDs: processIDs, addresses: addresses)
    }
}
