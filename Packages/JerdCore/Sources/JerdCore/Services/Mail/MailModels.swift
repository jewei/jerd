import Foundation

public struct MailRuntime: Codable, Equatable, Sendable {
    public let id: String
    public let version: String
    public let path: String
    public var executable: URL { URL(fileURLWithPath: path).appendingPathComponent("mailpit") }
    public init(id: String, version: String, path: String) {
        self.id = id; self.version = version; self.path = path
    }
}

public struct MailConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var runtime: MailRuntime?
    public var smtpPort: UInt16 = 1025
    public var webPort: UInt16 = 8025
    public init() {}
    public var inboxURL: URL { URL(string: "http://127.0.0.1:\(webPort)/")! }
    public var laravelSettings: String {
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
    public func validate() throws {
        guard schemaVersion == 1, smtpPort > 1023, webPort > 1023, smtpPort != webPort else {
            throw JerdError.invalid("Mail settings need two different ports from 1024 to 65535 and a supported format.")
        }
        if let runtime {
            guard DatabaseConfiguration.safeIdentifier(runtime.id), DatabaseConfiguration.safeIdentifier(runtime.version),
                  runtime.path.hasPrefix("/"), !runtime.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw JerdError.invalid("The Mailpit runtime record is invalid.")
            }
        }
    }
}

public enum MailState: Equatable, Sendable {
    case stopped, starting, running, stopping, failed(String)
    public var title: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .running: "Ready"
        case .stopping: "Stopping…"
        case .failed: "Failed"
        }
    }
}

public struct MailSnapshot: Sendable {
    public let configuration: MailConfiguration
    public let state: MailState
    public let processID: Int32?
}

public struct MailPaths: Sendable {
    public let root: URL
    public var inbox: URL { root.appendingPathComponent("inbox") }
    public var database: URL { inbox.appendingPathComponent("messages.sqlite") }
    public var identity: URL { inbox.appendingPathComponent("runtime.json") }
    public var initialized: URL { inbox.appendingPathComponent("initialized.json") }
    public var activeRun: URL { root.appendingPathComponent("active-run.json") }
    public var log: URL { root.appendingPathComponent("server.log") }
    public init(root: URL) { self.root = root }
}
