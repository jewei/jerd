/// The saved runtime record of a single-instance service, for example a Mailpit folder.
package protocol SingleServiceRuntime: Equatable, Sendable {
    /// True when the record is safe to save and to start.
    var isValid: Bool { get }
}
