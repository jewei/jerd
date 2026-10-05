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
}
