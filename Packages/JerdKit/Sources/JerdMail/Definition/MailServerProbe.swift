import Foundation
import JerdFoundation
import JerdProcess

/// The live readiness answers of Mailpit.
///
/// The information request uses an ephemeral loopback session in this process, so a waiting
/// start spawns no process until the web service answers. The SMTP check then runs `curl` once
/// per round, because `curl` is a complete SMTP client.
struct MailServerProbe: MailServerProbing {
    /// The largest information body.
    static let informationLimit = 65_536
    /// The limit of one information request.
    static let informationTimeout: TimeInterval = 2
    /// The limit of one SMTP check.
    static let smtpTimeout: Duration = .seconds(3)

    private static let session = URLSession(configuration: loopbackConfiguration())

    private let commands: any CommandRunning
    private let workingDirectory: URL

    /// - Parameter workingDirectory: the folder of the `curl` command, normally `mail/`.
    init(commands: any CommandRunning, workingDirectory: URL) {
        self.commands = commands
        self.workingDirectory = workingDirectory
    }

    func information(webPort: UInt16) async throws -> Data {
        guard let url = URL(string: "http://127.0.0.1:\(webPort)/api/v1/info") else {
            throw JerdError.invalid("Invalid Mailpit port.")
        }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        let (bytes, response) = try await Self.session.bytes(for: request, delegate: RedirectRefusal())
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw JerdError.unavailable("Mailpit did not answer its information request.")
        }
        var body = Data()
        for try await byte in bytes {
            guard body.count < Self.informationLimit else {
                throw JerdError.unavailable("The Mailpit information exceeds the size limit.")
            }
            body.append(byte)
        }
        return body
    }

    func smtpReply(smtpPort: UInt16) async throws -> String {
        let result = try await commands.run(
            Self.smtpRequest(port: smtpPort, in: workingDirectory), timeout: Self.smtpTimeout)
        guard result.succeeded else { throw JerdError.unavailable(result.diagnosticOutput) }
        return result.output
    }

    /// `curl` sends `NOOP` to the local SMTP service, without a proxy.
    static func smtpRequest(port: UInt16, in folder: URL) -> ProcessRequest {
        ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/curl"),
            arguments: [
                "--silent", "--show-error", "--max-time", "2", "--noproxy", "*",
                "--url", "smtp://127.0.0.1:\(port)", "--request", "NOOP",
            ], workingDirectory: folder)
    }

    /// An ephemeral session without proxies, cookies, or a cache.
    static func loopbackConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: 0, kCFNetworkProxiesHTTPSEnable as String: 0,
            kCFNetworkProxiesSOCKSEnable as String: 0,
        ]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = informationTimeout
        configuration.timeoutIntervalForResource = 3
        return configuration
    }
}
