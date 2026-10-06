import Darwin
import Foundation
import JerdDatabases
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

/// A real database manager on prepared runtimes, in a temporary data folder, on free loopback ports.
struct IntegrationRun {
    struct Pins: Decodable {
        struct Artifact: Decodable {
            let id: String
            let engine: DatabaseEngine
            let version: String
        }

        let artifacts: [Artifact]
    }

    let directory: TemporaryDirectory
    let layout: DatabasesLayout
    let manager: DatabaseManager
    let runtimes: [DatabaseRuntime]

    /// Reads `<source>/pins.json` and registers `<source>/<id>` for each artifact.
    init(runtimes source: URL) async throws {
        let pins = try JSONDecoder().decode(
            Pins.self, from: Data(contentsOf: source.appendingPathComponent("pins.json")))
        directory = try TemporaryDirectory(" database persistence ü")
        layout = DataLayout(root: directory.path("Jerd")).databases
        manager = DatabaseManager(layout: layout, effects: ServiceEffects(processes: ProcessSupervisor()))
        runtimes = pins.artifacts.map {
            DatabaseRuntime(
                id: $0.id, engine: $0.engine, version: $0.version, path: source.appendingPathComponent($0.id).path)
        }
        _ = try await manager.load()
        try await manager.registerRuntimes(runtimes)
    }

    func runtime(of service: DatabaseService) throws -> DatabaseRuntime {
        try #require(runtimes.first { $0.id == service.runtimeID })
    }

    func engine(of service: DatabaseService) throws -> any DatabaseEngineDefinition {
        DatabaseServiceDefinition.engine(
            runtime: try runtime(of: service), service: service,
            files: DatabaseInstanceFiles(layout: layout.instance(service.id)))
    }

    func credentials(of service: DatabaseService) throws -> DatabaseCredentials {
        try DatabaseCredentials.read(from: layout.instance(service.id).credentialsFile)
    }

    /// Runs a client command with the saved credentials and returns its trimmed output.
    func query(_ service: DatabaseService, _ command: [String]) async throws -> CommandResult {
        let request = try engine(of: service).clientRequest(command, credentials: try credentials(of: service))
        return try await CommandRunner().run(request, timeout: .seconds(5))
    }

    /// The trimmed output of a successful query.
    func value(_ service: DatabaseService, _ command: [String]) async throws -> String {
        let result = try await query(service, command)
        #expect(result.succeeded, "\(service.name): \(result.output)")
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A free loopback port above 1023, from the kernel.
    static func freePort() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = in_addr_t(0x7F00_0001).bigEndian
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, length) == 0 && getsockname(descriptor, $0, &length) == 0
            }
        }
        guard descriptor >= 0, bound else { throw JerdError.unavailable("Cannot find a free test port.") }
        return UInt16(bigEndian: address.sin_port)
    }
}
