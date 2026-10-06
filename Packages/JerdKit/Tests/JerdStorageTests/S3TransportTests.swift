import Foundation
import JerdFoundation
import JerdServiceKitTestSupport
import Testing

@testable import JerdStorage

/// Tests of the live transport against a small HTTP server on a loopback port.
@Suite struct S3TransportTests {
    static func request(_ server: LoopbackHTTPServer, _ path: String = "/") throws -> URLRequest {
        URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(server.port)\(path)")))
    }

    @Test func anAnswerGivesItsStatusAndCompleteBody() async throws {
        let body = Data(repeating: 65, count: 200_000)
        let server = try LoopbackHTTPServer { _ in LoopbackHTTPServer.response(status: 200, body: body) }
        defer { server.stop() }
        let response = try await S3Transport().send(try Self.request(server))
        #expect(response == S3Response(status: 200, body: body))
    }

    @Test func aRedirectIsReturnedAndNeverFollowed() async throws {
        let server = try LoopbackHTTPServer { _ in
            LoopbackHTTPServer.response(status: 307, headers: ["Location: /elsewhere"])
        }
        defer { server.stop() }
        let response = try await S3Transport().send(try Self.request(server))
        #expect(response.status == 307 && !response.succeeded)
        #expect(server.requests.count == 1)
    }

    @Test func aDeclaredBodyAboveTheLimitIsRefused() async throws {
        let server = try LoopbackHTTPServer { _ in
            LoopbackHTTPServer.response(status: 200, body: Data(repeating: 65, count: 2_048))
        }
        defer { server.stop() }
        await #expect(throws: StorageMessages.responseTooLarge) {
            try await S3Transport(responseLimit: 1_024).send(try Self.request(server))
        }
    }

    @Test func aStreamedBodyAboveTheLimitIsRefused() async throws {
        let server = try LoopbackHTTPServer { _ in
            let head = "HTTP/1.1 200 Test\r\nConnection: close\r\nTransfer-Encoding: chunked\r\n\r\n"
            let chunk = String(repeating: "A", count: 4_096)
            let chunks = String(repeating: "1000\r\n\(chunk)\r\n", count: 8) + "0\r\n\r\n"
            return Data((head + chunks).utf8)
        }
        defer { server.stop() }
        await #expect(throws: StorageMessages.responseTooLarge) {
            try await S3Transport(responseLimit: 10_000).send(try Self.request(server))
        }
    }

    @Test func cookiesAreNeverStoredOrSent() async throws {
        let server = try LoopbackHTTPServer { _ in
            LoopbackHTTPServer.response(status: 200, headers: ["Set-Cookie: session=secret; Path=/"])
        }
        defer { server.stop() }
        let transport = S3Transport()
        _ = try await transport.send(try Self.request(server))
        _ = try await transport.send(try Self.request(server))
        #expect(server.requests.count == 2)
        #expect(!server.requests.contains { $0.head.lowercased().contains("cookie") })
    }

    @Test func aClosedPortIsUnavailable() async throws {
        let server = try LoopbackHTTPServer { _ in Data() }
        let request = try Self.request(server)
        server.stop()
        await #expect {
            try await S3Transport().send(request)
        } throws: { error in
            (error as? JerdError)?.kind == .unavailable
        }
    }

    @Test func theSessionHasNoProxyCacheOrCookiesAndShortTimeouts() {
        let configuration = S3Transport.configuration()
        let proxies = configuration.connectionProxyDictionary ?? [:]
        for key in [kCFNetworkProxiesHTTPEnable, kCFNetworkProxiesHTTPSEnable, kCFNetworkProxiesSOCKSEnable] {
            #expect(proxies[key as String] as? Int == 0)
        }
        #expect(configuration.urlCache == nil && configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.timeoutIntervalForRequest == 5 && configuration.timeoutIntervalForResource == 8)
    }

    @Test func anInvalidatedTransportRefusesNewRequestsWithAMessage() async throws {
        let server = try LoopbackHTTPServer { _ in LoopbackHTTPServer.response(status: 200) }
        defer { server.stop() }
        let transport = S3Transport()
        #expect(try await transport.send(try Self.request(server)).status == 200)
        transport.invalidate()
        transport.invalidate()
        await #expect(throws: StorageMessages.sessionEnded) { try await transport.send(try Self.request(server)) }
        #expect(server.requests.count == 1)
    }

    @Test func anInvalidationEndsARequestInFlightWithAMessage() async throws {
        let server = try LoopbackHTTPServer { _ in
            Thread.sleep(forTimeInterval: 2)
            return LoopbackHTTPServer.response(status: 200)
        }
        defer { server.stop() }
        let transport = S3Transport()
        let request = try Self.request(server)
        let pending = Task { try await transport.send(request) }
        #expect(await eventually { server.requests.count == 1 })
        transport.invalidate()
        await #expect(throws: StorageMessages.sessionEnded) { try await pending.value }
    }
}
