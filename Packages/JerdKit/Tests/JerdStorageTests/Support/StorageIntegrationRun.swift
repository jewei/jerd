import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@testable import JerdStorage

/// A real storage manager on a prepared RustFS runtime, in a temporary data folder, on free
/// loopback ports.
struct StorageIntegrationRun {
    let directory: TemporaryDirectory
    let layout: DataLayout
    let manager: StorageManager
    let runtime: StorageRuntime
    let transport = S3Transport()

    init(runtime folder: URL) async throws {
        directory = try TemporaryDirectory(" storage persistence café")
        layout = DataLayout(root: directory.path("Jerd"))
        manager = Self.manager(layout)
        runtime = StorageRuntime(id: "rustfs-1.0.0-arm64", version: "1.0.0", path: folder.path)
        _ = try await manager.load()
        try await manager.registerRuntime(runtime)
        try await manager.edit(ports: try Self.freePorts())
    }

    static func manager(_ layout: DataLayout) -> StorageManager {
        StorageManager(layout: layout, effects: ServiceEffects(processes: ProcessSupervisor()))
    }

    var storage: StorageLayout { layout.storage }

    /// A client of the running service with `credentials`, or the saved ones.
    func client(_ credentials: StorageCredentials? = nil) async throws -> S3Client {
        let saved = try await manager.credentials()
        return S3Client(
            port: await manager.snapshot().settings.apiPort, credentials: credentials ?? saved, sender: transport)
    }

    /// Two different free loopback ports above 1023, from the kernel.
    static func freePorts() throws -> StoragePorts {
        let first = try freePort()
        var second = try freePort()
        while second == first { second = try freePort() }
        return StoragePorts(api: first, console: second)
    }

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
