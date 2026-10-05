import Darwin
import JerdServiceKit

/// The settings and the service state, for the Mail page.
public struct MailSnapshot: Equatable, Sendable {
    public let settings: MailSettings
    public let state: ServiceState

    public init(settings: MailSettings, state: ServiceState) {
        self.settings = settings
        self.state = state
    }

    /// The PID of the owned Mailpit process, also while it is stuck.
    public var processID: pid_t? { state.processID }
}
