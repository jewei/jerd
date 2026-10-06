import Foundation

/// The content of `mail/settings.json`.
///
/// The synthesized `Codable` form is the compatibility contract: `schemaVersion`, `smtpPort`, and
/// `webPort` are required on decode, and `runtime` is left out while it is nil.
public struct MailSettings: Codable, Equatable, Sendable {
    /// The only settings version that this build reads and writes.
    public static let supportedVersion = 1
    /// The default ports of a new inbox.
    public static let defaultPorts = MailPorts(smtp: 1_025, web: 8_025)

    public var schemaVersion = MailSettings.supportedVersion
    public var runtime: MailRuntime?
    public var smtpPort: UInt16 = MailSettings.defaultPorts.smtp
    public var webPort: UInt16 = MailSettings.defaultPorts.web

    public init(runtime: MailRuntime? = nil, ports: MailPorts = MailSettings.defaultPorts) {
        self.runtime = runtime
        smtpPort = ports.smtp
        webPort = ports.web
    }

    /// The SMTP and web ports.
    public var ports: MailPorts {
        get { MailPorts(smtp: smtpPort, web: webPort) }
        set {
            smtpPort = newValue.smtp
            webPort = newValue.web
        }
    }

    /// The inbox page: `http://127.0.0.1:<web>/`.
    public var inboxURL: URL {
        URL(string: "http://127.0.0.1:\(webPort)/") ?? URL(fileURLWithPath: "/")
    }

    /// The Laravel `.env` lines that send mail to the local inbox. Each line ends with a newline.
    public var laravelEnvironment: String {
        """
        MAIL_MAILER=smtp
        MAIL_SCHEME=null
        MAIL_URL=null
        MAIL_HOST=127.0.0.1
        MAIL_PORT=\(smtpPort)
        MAIL_USERNAME=null
        MAIL_PASSWORD=null
        MAIL_ENCRYPTION=null
        MAIL_FROM_ADDRESS="hello@jerd.test"
        MAIL_FROM_NAME="Jerd"

        """
    }

    /// The rules of every load and save: a supported version, two different ports from 1024, and a
    /// valid runtime record.
    public func validate() throws {
        guard schemaVersion == Self.supportedVersion, ports.isValid else { throw MailMessages.settingsInvalid }
        if let runtime, !runtime.isValid { throw MailMessages.runtimeRecordInvalid }
    }
}
