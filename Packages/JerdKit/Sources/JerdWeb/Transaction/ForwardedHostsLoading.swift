/// Reads the saved forwarded hosts. JerdLive reads the saved local tunnel routes; it never
/// connects them.
package protocol ForwardedHostsLoading: Sendable {
    /// - Throws: When the saved routes cannot be read. The file stays as it is.
    func loadForwardedHosts() async throws -> ForwardedHosts
}
