import Foundation
import Testing

@testable import JerdDevKit

@Suite("Loopback file server")
struct LoopbackFileServerTests {
    private func response(_ head: String, files: [String: String] = ["appcast.xml": "<rss/>"]) -> String {
        let data = StaticFileResponse.response(to: Data(head.utf8)) { files[$0].map { Data($0.utf8) } }
        return String(decoding: data, as: UTF8.self)
    }

    @Test("Answers GET of a plain file name with its bytes and length")
    func servesAFile() {
        let text = response("GET /appcast.xml HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Type: application/xml\r\nContent-Length: 6\r\n"))
        #expect(text.hasSuffix("\r\n\r\n<rss/>"))
    }

    @Test("HEAD has the headers without the body")
    func head() {
        #expect(response("HEAD /appcast.xml HTTP/1.1\r\n\r\n").hasSuffix("Connection: close\r\n\r\n"))
    }

    @Test(
        "Refuses paths outside the folder, hidden files, and missing files",
        arguments: ["/../etc/passwd", "/a/b", "/.events", "/", "appcast.xml", "/missing.zip", "/%2e%2e"])
    func refusesOtherPaths(_ target: String) {
        #expect(response("GET \(target) HTTP/1.1\r\n\r\n").hasPrefix("HTTP/1.1 404 Not Found"))
    }

    @Test("Refuses other methods and malformed or oversized requests")
    func refusesBadRequests() {
        #expect(response("POST /appcast.xml HTTP/1.1\r\n\r\n").hasPrefix("HTTP/1.1 405"))
        #expect(response("GET /appcast.xml\r\n\r\n").hasPrefix("HTTP/1.1 400"))
        let large = "GET /appcast.xml HTTP/1.1\r\nX: " + String(repeating: "a", count: 20_000) + "\r\n\r\n"
        #expect(response(large).hasPrefix("HTTP/1.1 400"))
    }

    @Test("A query string does not change the file")
    func ignoresQuery() {
        #expect(StaticFileResponse.fileName(inTarget: "/appcast.xml?x=1") == "appcast.xml")
    }

    @Test("Serves a folder on 127.0.0.1 and stops")
    func servesOverLoopback() async throws {
        let folder = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try TestFixtures.write("feed", to: "appcast.xml", in: folder)
        let server = LoopbackFileServer()
        let base = try await server.start(serving: folder)
        #expect(base.host == "127.0.0.1" && (base.port ?? 0) > 1023)
        let session = URLSession(configuration: .ephemeral)
        let (data, answer) = try await session.data(from: base.appending(path: "appcast.xml"))
        #expect(String(decoding: data, as: UTF8.self) == "feed")
        #expect((answer as? HTTPURLResponse)?.statusCode == 200)
        let (_, missing) = try await session.data(from: base.appending(path: "other.zip"))
        #expect((missing as? HTTPURLResponse)?.statusCode == 404)
        await server.stop()
        await #expect(throws: (any Error).self) {
            _ = try await session.data(from: base.appending(path: "appcast.xml"))
        }
    }
}
