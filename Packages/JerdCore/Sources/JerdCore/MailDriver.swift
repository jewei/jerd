import Foundation

public enum MailDriver {
    public static func server(configuration: MailConfiguration, runtime: MailRuntime, paths: MailPaths) -> ProcessRequest {
        // ProcessSupervisor supplies a clean environment. No relay, forwarding,
        // webhook, POP3, or user-provided Mailpit configuration is inherited.
        ProcessRequest(executable: runtime.executable, arguments: [
            "--database", paths.database.path,
            "--smtp", "127.0.0.1:\(configuration.smtpPort)",
            "--listen", "127.0.0.1:\(configuration.webPort)",
            "--allowed-hosts", "127.0.0.1,localhost", "--label", "Jerd",
            "--max", "0", "--disable-version-check", "--smtp-disable-rdns",
            "--block-remote-css-and-fonts"
        ], directory: paths.root)
    }

    public static func smtpProbe(configuration: MailConfiguration, paths: MailPaths) -> ProcessRequest {
        ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/curl"), arguments: [
            "--silent", "--show-error", "--max-time", "2", "--noproxy", "*",
            "--url", "smtp://127.0.0.1:\(configuration.smtpPort)", "--request", "NOOP"
        ], directory: paths.root)
    }

    public static func httpProbe(configuration: MailConfiguration, paths: MailPaths) -> ProcessRequest {
        ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/curl"), arguments: [
            "--silent", "--show-error", "--fail", "--max-time", "2", "--noproxy", "*",
            "--url", configuration.inboxURL.appendingPathComponent("api/v1/info").absoluteString
        ], directory: paths.root)
    }

    public static func send(configuration: MailConfiguration, paths: MailPaths, message: URL) -> ProcessRequest {
        ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/curl"), arguments: [
            "--silent", "--show-error", "--max-time", "5", "--noproxy", "*",
            "--url", "smtp://127.0.0.1:\(configuration.smtpPort)",
            "--mail-from", "hello@jerd.test", "--mail-rcpt", "inbox@jerd.test", "--upload-file", message.path
        ], directory: paths.root)
    }
}
