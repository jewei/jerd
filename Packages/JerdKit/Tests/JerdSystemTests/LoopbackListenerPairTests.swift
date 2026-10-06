import Darwin
import Foundation
import JerdFoundation
import Testing
import os

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

    private func freePort() throws -> UInt16 {
        let pair = try LoopbackListenerPair.bind(httpPort: 0, httpsPort: 0)
        defer { pair.close() }
        return try pair.ports().http
    }

    /// Leaves server-side connections of a closed listener in TIME_WAIT on `port`.
    private func lingerConnections(on port: UInt16) throws {
        let pair = try LoopbackListenerPair.bind(httpPort: port, httpsPort: 0)
        defer { pair.close() }
        let client = try #require(TestSocket.connect(port: port))
        defer { close(client) }
        let accepted = accept(pair.http.fileDescriptor, nil, nil)
        try #require(accepted >= 0)
        close(accepted)
    }

    /// The probe finds a loopback listener and nothing on a closed port (review L2: no wildcard bind).
    @Test func theProbeFindsALoopbackListenerOnly() throws {
        let pair = try LoopbackListenerPair.bind(httpPort: 0, httpsPort: 0)
        let port = try pair.ports().http
        #expect(LoopbackSocket.accepts(port: port))
        pair.close()
        #expect(!LoopbackSocket.accepts(port: port))
    }

    /// Fixed problem 10 and review L3: the kernel refuses the first bind atomically when any listener,
    /// also a wildcard one, holds the port; the probe then names the other listener.
    @Test func aBusyFixedPortIsRefusedWithTheListenerMessage() throws {
        let blocker = try LoopbackListenerPair.bind(httpPort: 0, httpsPort: 0)
        defer { blocker.close() }
        let port = try blocker.ports().http
        #expect(
            throws: JerdError.unavailable(
                "Loopback port \(port) already has a listener. Stop the other service in its own app, then retry.")
        ) {
            try LoopbackListenerPair.bind(httpPort: port, httpsPort: 0)
        }
    }

    /// Fixed review L3: a free port is bound without a check-then-bind probe, so no listener can
    /// appear between a check and the bind.
    @Test func aFreeFixedPortIsBoundWithoutTheProbe() throws {
        let port = try freePort()
        let probed = OSAllocatedUnfairLock(initialState: [UInt16]())
        let pair = try LoopbackListenerPair.bind(httpPort: port, httpsPort: 0) { probedPort in
            probed.withLock { $0.append(probedPort) }
            return LoopbackSocket.accepts(port: probedPort)
        }
        defer { pair.close() }
        #expect(try pair.ports().http == port)
        #expect(probed.withLock { $0 }.isEmpty)
    }

    /// Review L3: a port that only lingering connections hold is probed, then bound again.
    @Test func aPortHeldOnlyByLingeringConnectionsIsBoundAgain() throws {
        let port = try freePort()
        try lingerConnections(on: port)
        let probed = OSAllocatedUnfairLock(initialState: [UInt16]())
        let pair = try LoopbackListenerPair.bind(httpPort: port, httpsPort: 0) { probedPort in
            probed.withLock { $0.append(probedPort) }
            return LoopbackSocket.accepts(port: probedPort)
        }
        defer { pair.close() }
        #expect(try pair.ports().http == port)
        #expect(probed.withLock { $0 } == [port])
    }

    @Test func standardPortsAreEightyAndFourFortyThree() {
        #expect(LoopbackListenerPair.standardPorts == (80, 443))
    }
}
