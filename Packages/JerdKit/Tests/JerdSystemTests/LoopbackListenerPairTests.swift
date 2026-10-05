import Darwin
import Foundation
import JerdFoundation
import Testing

@testable import JerdSystem

@Suite struct LoopbackListenerPairTests {
    @Test func bindsTwoDistinctEphemeralLoopbackPorts() throws {
        let pair = try LoopbackListenerPair.bind(httpPort: 0, httpsPort: 0)
        defer { pair.close() }
        let ports = try pair.ports()
        #expect(ports.http > 1_023 && ports.https > 1_023 && ports.http != ports.https)
        #expect(fcntl(pair.http.fileDescriptor, F_GETFD) & FD_CLOEXEC != 0)
    }

    @Test func refusesTheSamePortTwice() {
        #expect(throws: JerdError.invalid("HTTP and HTTPS need different sockets.")) {
            try LoopbackListenerPair.bind(httpPort: 50_000, httpsPort: 50_000)
        }
    }

    @Test func refusesHandlesThatAreNotListeningLoopbackSockets() throws {
        let message = JerdError.invalid("Expected a listening IPv4 loopback TCP socket.")
        #expect(throws: message) { try LoopbackListenerPair(http: .nullDevice, https: .nullDevice).ports() }
        // Fixed spec B problem 20: a bound socket that does not listen is refused too.
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = in_addr_t(0x7F00_0001).bigEndian
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        #expect(bound == 0)
        let listening = try LoopbackListenerPair.bind(httpPort: 0, httpsPort: 0)
        defer { listening.close() }
        #expect(throws: message) { try LoopbackListenerPair(http: handle, https: listening.https).ports() }
    }

    @Test func aLiveListenerBlocksASecondBindAndARestartSucceeds() throws {
        let first = try LoopbackListenerPair.bind(httpPort: 0, httpsPort: 0)
        let ports = try first.ports()
        #expect(throws: JerdError.self) { try LoopbackListenerPair.bind(httpPort: ports.http, httpsPort: ports.https) }
        first.close()
        let second = try LoopbackListenerPair.bind(httpPort: ports.http, httpsPort: ports.https)
        defer { second.close() }
        #expect(try second.ports() == ports)
    }

    @Test func aFailedSecondBindClosesTheFirstListener() throws {
        let blocker = try LoopbackListenerPair.bind(httpPort: 0, httpsPort: 0)
        defer { blocker.close() }
        let taken = try blocker.ports().https
        let free = try LoopbackListenerPair.bind(httpPort: 0, httpsPort: 0)
        let httpPort = try free.ports().http
        free.close()
        #expect(throws: JerdError.self) { try LoopbackListenerPair.bind(httpPort: httpPort, httpsPort: taken) }
        let again = try LoopbackListenerPair.bind(httpPort: httpPort, httpsPort: 0)
        again.close()
    }

    /// Fixed problem 10: a wildcard listener on the port is found before the loopback bind.
    @Test func aWildcardListenerOnThePortIsRefused() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        #expect(bound == 0 && listen(descriptor, 4) == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        let port = UInt16(bigEndian: address.sin_port)
        #expect(
            throws: JerdError.unavailable(
                "Loopback port \(port) already has a listener. Stop the other service in its own app, then retry.")
        ) {
            try LoopbackListenerPair.bind(httpPort: port, httpsPort: 0)
        }
    }

    @Test func standardPortsAreEightyAndFourFortyThree() {
        #expect(LoopbackListenerPair.standardPorts == (80, 443))
    }
}
