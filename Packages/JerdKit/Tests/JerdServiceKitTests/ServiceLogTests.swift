import Foundation
import JerdServiceKit
import JerdServiceKitTestSupport
import JerdTestSupport
import Testing

@Suite struct ServiceLogTests {
    @Test func rotationKeepsTheOutputOfThePreviousRun() throws {
        let directory = try TemporaryDirectory(" service kit ü")
        defer { directory.remove() }
        let log = ServiceLog(file: directory.path("server.log"), previousFile: directory.path("server.previous.log"))
        try write("first run", to: directory.path("server.log"))
        try write("older run", to: directory.path("server.previous.log"))
        try log.rotate()
        #expect(!exists(directory.path("server.log")))
        #expect(text(directory.path("server.previous.log")) == "first run")
        try log.rotate()
        #expect(text(directory.path("server.previous.log")) == "first run")
    }

    @Test func theTailRedactsASecretThatCrossesTheCut() throws {
        let directory = try TemporaryDirectory(" service kit ü")
        defer { directory.remove() }
        let secret = "0123456789abcdef0123456789abcdef"
        let body = "header " + secret + String(repeating: "y", count: ServiceLog.tailLimit - 10)
        try write(body, to: directory.path("server.log"))
        let log = ServiceLog(file: directory.path("server.log"), previousFile: directory.path("server.previous.log"))
        let tail = log.tail(redacting: [secret], fallback: "fallback")
        #expect(tail.count == ServiceLog.tailLimit)
        #expect(!tail.contains("0123"))
        #expect(!tail.contains("cdef"))
    }

    @Test func aMissingOrEmptyLogGivesTheFallback() throws {
        let directory = try TemporaryDirectory(" service kit ü")
        defer { directory.remove() }
        let log = ServiceLog(file: directory.path("server.log"), previousFile: directory.path("server.previous.log"))
        #expect(log.tail(redacting: [], fallback: "Open the log.") == "Open the log.")
        try write("", to: directory.path("server.log"))
        #expect(log.tail(redacting: [], fallback: "Open the log.") == "Open the log.")
        try write("ready\n", to: directory.path("server.log"))
        #expect(log.tail(redacting: [], fallback: "Open the log.") == "ready\n")
    }
}
