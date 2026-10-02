import Foundation
import Testing
import Darwin
@testable import JerdCore

struct SystemSetupTests {
    @Test func multipleHostsPreserveUnrelatedMappings() throws {
        let original = Data("127.0.0.1 localhost\n10.0.0.1 keep.test".utf8)
        let added = try HostsDocument.replacing(original, hostnames: ["two.test", "one.test"], expectedHostnames: [])
        #expect(HostsDocument.containsRegistrations(["one.test", "two.test"], in: added))
        let remaining = try HostsDocument.replacing(added, hostnames: ["two.test"], expectedHostnames: ["one.test", "two.test"])
        #expect(!String(decoding: remaining, as: UTF8.self).contains("one.test"))
        #expect(try HostsDocument.replacing(remaining, hostnames: [], expectedHostnames: ["two.test"]) == original)
        #expect(throws: JerdError.self) {
            try HostsDocument.replacing(added, hostnames: ["one.test"], expectedHostnames: ["one.test"])
        }
    }

    @Test(arguments: ["127.0.0.1 localhost\n# keep\n", "127.0.0.1 localhost", "# café 项目\r\n", ""])
    func hostsRoundTripPreservesOtherBytes(_ contents: String) throws {
        let original = Data(contents.utf8)
        let added = try HostsDocument.replacing(original, hostname: "demo.test", expectedHostname: nil)
        #expect(HostsDocument.containsRegistration("demo.test", in: added))
        let edited = try HostsDocument.replacing(added, hostname: "shop.test", expectedHostname: "demo.test")
        #expect(HostsDocument.containsRegistration("shop.test", in: edited))
        #expect(!String(decoding: edited, as: UTF8.self).contains("demo.test"))
        #expect(try HostsDocument.replacing(edited, hostname: nil, expectedHostname: "shop.test") == original)
    }

    @Test(arguments: ["10.0.0.1 demo.test\n", "127.0.0.1 demo.test\n", "# BEGIN JERD\n", "# END JERD\n",
                      "# BEGIN JERD\n127.0.0.1 other.test\n# END JERD\n"])
    func refusesConflictingOrUntrackedHosts(_ text: String) {
        #expect(throws: (any Error).self) { try HostsDocument.replacing(Data(text.utf8), hostname: "demo.test", expectedHostname: nil) }
    }

    @Test func atomicHostsMetadataAndConflict() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("hosts")
        let original = Data("127.0.0.1 localhost\n".utf8)
        try original.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
        let attribute = "com.jerd.test"
        let value = Array("keep".utf8)
        #expect(value.withUnsafeBytes { setxattr(url.path, attribute, $0.baseAddress, $0.count, 0, 0) } == 0)
        let store = AtomicHostsFile(url: url, expectedOwner: getuid())
        let next = try HostsDocument.replacing(original, hostname: "demo.test", expectedHostname: nil)
        try store.replace(expected: original, with: next)
        #expect(try store.read() == next)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path)
            .allSatisfy { !$0.hasPrefix(".jerd-hosts-") })
        let metadata = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((metadata[.posixPermissions] as? NSNumber)?.intValue == 0o640)
        var read = [UInt8](repeating: 0, count: 4)
        #expect(getxattr(url.path, attribute, &read, read.count, 0, 0) == 4)
        #expect(read == value)
        #expect(throws: (any Error).self) { try store.replace(expected: original, with: Data()) }
        #expect(try store.read() == next)
        try store.replace(expected: next, with: original)
        #expect(try store.read() == original)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: url)
        #expect(throws: (any Error).self) { try AtomicHostsFile(url: alias, expectedOwner: getuid()).read() }
    }

    @Test func atomicHostsRestoresRacedDestination() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("hosts")
        let original = Data("127.0.0.1 localhost\n".utf8)
        let raced = Data("127.0.0.1 raced.test\n".utf8)
        try original.write(to: url)
        let store = AtomicHostsFile(url: url, expectedOwner: getuid(), preExchange: {
            try raced.write(to: url, options: .atomic)
        })

        #expect(throws: (any Error).self) {
            try store.replace(expected: original, with: Data("127.0.0.1 replacement.test\n".utf8))
        }
        #expect(try Data(contentsOf: url) == raced)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path)
            .allSatisfy { !$0.hasPrefix(".jerd-hosts-") })
    }

    @Test func rejectsNonJerdCertificateAndSigningInput() throws {
        #expect(throws: (any Error).self) { try InstallationCertificate.validate(Data("not a cert".utf8), installationID: UUID()) }
        #expect(throws: (any Error).self) { try SystemService.signingRequirement(identifier: "another.app", teamID: "ABCDEFGHIJ") }
        #expect(throws: (any Error).self) { try SystemService.signingRequirement(identifier: SystemService.appIdentifier, teamID: "\" or true") }
        #expect(try SystemService.signingRequirement(identifier: SystemService.appIdentifier, teamID: "ABCDEFGHIJ").contains("anchor apple generic"))
    }

    @Test func inheritedSocketPorts() throws {
        let sockets = try ListeningSockets.bind(httpPort: 0, httpsPort: 0)
        defer { sockets.close() }
        let ports = try sockets.ports()
        #expect(ports.http > 1023 && ports.https > 1023 && ports.http != ports.https)
        let invalid = ListeningSockets(http: .nullDevice, https: .nullDevice)
        #expect(throws: (any Error).self) { try invalid.ports() }
    }

    @Test func listenerRestartAfterConnectionDoesNotShareLivePort() async throws {
        let first = try ListeningSockets.bind(httpPort: 0, httpsPort: 0)
        let ports = try first.ports()
        #expect(throws: (any Error).self) { try ListeningSockets.bind(httpPort: ports.http, httpsPort: ports.https) }
        let client = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(client) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = ports.https.bigEndian
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        #expect(connected == 0)
        let accepted = accept(first.https.fileDescriptor, nil, nil)
        #expect(accepted >= 0)
        shutdown(accepted, SHUT_WR)
        var byte: UInt8 = 0
        #expect(read(client, &byte, 1) == 0)
        shutdown(client, SHUT_WR)
        #expect(read(accepted, &byte, 1) == 0)
        close(accepted)
        first.close()
        // Other tests spawn processes concurrently. Allow descriptor cleanup
        // to finish, while keeping this far below TCP's TIME_WAIT duration.
        let deadline = ContinuousClock.now + .seconds(1)
        while true {
            do {
                let restarted = try ListeningSockets.bind(httpPort: ports.http, httpsPort: ports.https)
                restarted.close()
                break
            } catch {
                guard ContinuousClock.now < deadline else { throw error }
                try await Task.sleep(for: .milliseconds(5))
            }
        }
    }
}
