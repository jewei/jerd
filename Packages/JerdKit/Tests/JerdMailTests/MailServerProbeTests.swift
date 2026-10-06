import Foundation
import JerdFoundation
import JerdProcess
import Testing

@testable import JerdMail

@Suite struct MailServerProbeTests {
    static let folder = URL(fileURLWithPath: "/Users/me/Library/Application Support/Jerd/mail")

    static func probe(
        _ commands: ScriptedCommands = ScriptedCommands { _ in CommandResult(status: 0, output: "") }
    )
        -> MailServerProbe
    {
        MailServerProbe(commands: commands, workingDirectory: folder)
    }

    @Test func theInformationRequestReadsTheLoopbackAPI() async throws {
        let body = Data("{\"Version\":\"v1.31.3\"}".utf8)
        let server = try LoopbackHTTPServer { _ in LoopbackHTTPServer.response(status: 200, body: body) }
        defer { server.stop() }
        #expect(try await Self.probe().information(webPort: server.port) == body)
        let request = try #require(server.requests.first)
        #expect(request.requestLine == "GET /api/v1/info HTTP/1.1")
        #expect(!request.head.lowercased().contains("cookie"))
    }

    @Test(arguments: [302, 403, 500])
    func anyAnswerOutside2xxIsNotReadyAndRedirectsAreNotFollowed(_ status: Int) async throws {
        let server = try LoopbackHTTPServer { request in
            if request.requestLine.hasPrefix("GET /elsewhere") {
                return LoopbackHTTPServer.response(status: 200, body: Data("{}".utf8))
            }
            return LoopbackHTTPServer.response(status: status, headers: ["Location: /elsewhere"])
        }
        defer { server.stop() }
        await #expect(throws: JerdError.unavailable("Mailpit did not answer its information request.")) {
            try await Self.probe().information(webPort: server.port)
        }
        #expect(server.requests.count == 1)
    }

    @Test func anOversizedInformationAnswerIsRefused() async throws {
        let body = Data(repeating: 32, count: MailServerProbe.informationLimit + 1)
        let server = try LoopbackHTTPServer { _ in LoopbackHTTPServer.response(status: 200, body: body) }
        defer { server.stop() }
        await #expect(throws: JerdError.unavailable("The Mailpit information exceeds the size limit.")) {
            try await Self.probe().information(webPort: server.port)
        }
    }

    @Test func theSMTPCheckSendsNOOPWithCurlWithoutAProxy() async throws {
        let commands = ScriptedCommands { _ in CommandResult(status: 0, output: "250 2.0.0 Ok\r\n") }
        #expect(try await Self.probe(commands).smtpReply(smtpPort: 1_026) == "250 2.0.0 Ok\r\n")
        let request = try #require(commands.requests.first)
        #expect(request.executable.path == "/usr/bin/curl")
        #expect(
            request.arguments == [
                "--silent", "--show-error", "--max-time", "2", "--noproxy", "*", "--url", "smtp://127.0.0.1:1026",
                "--request", "NOOP",
            ])
        #expect(request.workingDirectory == Self.folder)
    }

    @Test func aFailedSMTPCheckThrowsTheCurlDiagnostics() async throws {
        let commands = ScriptedCommands { _ in CommandResult(status: 7, output: "curl: (7) Failed to connect") }
        await #expect(throws: JerdError.unavailable("curl: (7) Failed to connect")) {
            try await Self.probe(commands).smtpReply(smtpPort: 1_026)
        }
    }

    @Test func theSessionUsesNoProxyCookiesOrCache() {
        let configuration = MailServerProbe.loopbackConfiguration()
        #expect(configuration.connectionProxyDictionary?[kCFNetworkProxiesHTTPEnable as String] as? Int == 0)
        #expect(configuration.connectionProxyDictionary?[kCFNetworkProxiesHTTPSEnable as String] as? Int == 0)
        #expect(configuration.connectionProxyDictionary?[kCFNetworkProxiesSOCKSEnable as String] as? Int == 0)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.urlCache == nil)
        #expect(configuration.timeoutIntervalForRequest == 2)
    }
}
