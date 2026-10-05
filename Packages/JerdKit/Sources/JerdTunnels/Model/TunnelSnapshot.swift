import JerdFoundation

/// What the app shows for one registration: its settings, its state, and the PID of an owned connector.
public struct TunnelSnapshot: Equatable, Sendable {
    public let registration: TunnelRegistration
    public let state: TunnelState
    /// The PID of the connector that Jerd owns. It stays set after a failed graceful stop.
    public let processID: Int32?

    public init(registration: TunnelRegistration, state: TunnelState, processID: Int32? = nil) {
        self.registration = registration
        self.state = state
        self.processID = processID
    }

    /// Why the saved settings need an edit, or nil. An earlier build could save a value that the
    /// current rules refuse, for example an IP address as hostname. Such a tunnel still loads and
    /// connects; the app shows this message, and Save requires a valid value.
    public var settingsIssue: String? {
        do {
            try registration.validate()
            return nil
        } catch {
            return FailureDetail.describe(error)
        }
    }
}
