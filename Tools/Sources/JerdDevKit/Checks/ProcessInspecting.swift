/// Reads the executable of a process and sends it SIGTERM. The harness stops only processes whose
/// executable is its own test app, never by name. `LiveProcessInspector` is the live type.
protocol ProcessInspecting: Sendable {
    /// The absolute executable path of a live process, or nil when the process does not exist.
    func executablePath(of pid: Int32) -> String?
    /// Sends SIGTERM. Returns false when the process does not exist any more.
    func terminate(_ pid: Int32) -> Bool
}
