import JerdFoundation
import JerdMail
import JerdServiceKit
import JerdUI

/// The Mailpit inbox in memory. It records each call and answers with the configured behavior.
public actor InMemoryMail: MailPort {
    public var settings: MailSettings
    public var state: ServiceState
    public var hasData: Bool
    public var loadFailure: String?
    public var startBehavior = ServiceBehavior.succeed
    public var stopBehavior = ServiceBehavior.succeed
    /// When set, the test email, the port suggestion, and the port change throw this message.
    public var failure: String?
    public var suggestion = MailPorts(smtp: 1026, web: 8026)
    public private(set) var calls: [String] = []

    public init(settings: MailSettings = MailSettings(), state: ServiceState = .stopped, hasData: Bool = false) {
        self.settings = settings
        self.state = state
        self.hasData = hasData
    }

    public func configure(_ change: @Sendable (isolated InMemoryMail) -> Void) {
        change(self)
    }

    public func load() async throws -> MailSnapshot {
        calls.append("load")
        if let loadFailure { throw JerdError.corrupt(loadFailure) }
        return MailSnapshot(settings: settings, state: state)
    }

    public func snapshot() async -> MailSnapshot { MailSnapshot(settings: settings, state: state) }

    public func files() async -> ServiceFiles {
        SampleServices.files("mail", data: "inbox", hasData: hasData)
    }

    public func start() async throws {
        calls.append("start")
        switch startBehavior {
        case .succeed, .stuck:
            state = .running(pid: 4301)
            hasData = true
        case .fail(let reason):
            state = .failed(reason: reason)
            throw JerdError.processFailed(reason)
        case .suspend:
            try await ServiceBehavior.waitForCancellation()
        }
    }

    public func stop() async throws {
        calls.append("stop")
        do {
            state = try await ServiceStop.apply(stopBehavior, to: state)
        } catch let error as StuckError {
            state = error.state
            throw error
        }
    }

    public func sendTestEmail() async throws {
        calls.append("test email")
        if let failure { throw JerdError.unavailable(failure) }
    }

    public func suggestedPorts() async throws -> MailPorts {
        if let failure { throw JerdError.unavailable(failure) }
        return suggestion
    }

    public func edit(ports: MailPorts) async throws {
        calls.append("edit \(ports.smtp) \(ports.web)")
        if let failure { throw JerdError.unavailable(failure) }
        settings.ports = ports
    }
}
