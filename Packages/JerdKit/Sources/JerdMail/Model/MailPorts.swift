import JerdProcess

/// The two loopback ports of the inbox: SMTP for applications and HTTP for the inbox page.
public struct MailPorts: Equatable, Hashable, Sendable {
    public var smtp: UInt16
    public var web: UInt16

    public init(smtp: UInt16, web: UInt16) {
        self.smtp = smtp
        self.web = web
    }

    /// Both ports are 1024 or above and they differ.
    public var isValid: Bool {
        smtp >= LoopbackPortGuard.minimumPort && web >= LoopbackPortGuard.minimumPort && smtp != web
    }

    /// The ports in the order that a start checks them.
    public var ordered: [UInt16] { [smtp, web] }
}
