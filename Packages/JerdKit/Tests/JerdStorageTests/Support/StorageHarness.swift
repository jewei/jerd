import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import JerdStorage
import JerdTestSupport
import os

/// A storage manager with fake processes, commands, `lsof`, and an in-memory S3 service, in a
/// temporary data folder. A started fake RustFS writes its volume format file, as RustFS does.
final class StorageHarness: Sendable {
    static let format = Data("{\"version\":\"1\",\"format\":\"xl-single\"}".utf8)
    static let date = Date(timeIntervalSince1970: 1_369_353_600)

    let directory: TemporaryDirectory
    let layout: DataLayout
    let processes = FakeProcessController()
    let lsof: StorageLsof
    let commands: ScriptedCommands
    let server = FakeS3Server()
    let system = FakeSystem()
    let clock = FakeTimeKeeper()
    let runtime: StorageRuntime
    private let version = OSAllocatedUnfairLock(initialState: "1.0.0")

    init() async throws {
        let directory = try TemporaryDirectory(" service kit ü")
        self.directory = directory
        layout = DataLayout(root: directory.path("Jerd"))
        try OwnedDirectory.create(layout.root)
        runtime = StorageRuntime(
            id: "rustfs-1.0.0-arm64", version: "1.0.0", path: directory.path("runtimes/rustfs-1.0.0").path)
        let lsof = StorageLsof(processes: processes)
        self.lsof = lsof
        let version = version
        commands = ScriptedCommands { request in
            if request.executable.lastPathComponent == "lsof" { return await lsof.answer(request.arguments) }
            return CommandResult(status: 0, output: "rustfs \(version.withLock { $0 })\nbuild time   : 2026-09-16\n")
        }
        let format = layout.storage.formatFile
        await processes.setExitScript { _ in
            guard !FileManager.default.fileExists(atPath: format.path) else { return nil }
            try FileManager.default.createDirectory(
                at: format.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.format.write(to: format)
            return nil
        }
    }

    deinit { directory.remove() }

    var storage: StorageLayout { layout.storage }

    /// The version that every fake `rustfs --version` prints.
    func setVersion(_ text: String) { version.withLock { $0 = text } }

    func effects() -> ServiceEffects {
        let probe = LoopbackProbe(isAccepting: { _ in false }, requireBindable: { _ in })
        return ServiceEffects(
            processes: processes, commands: commands, ports: LoopbackPortGuard(commands: commands, probe: probe),
            startGate: StartGate(observer: system.observer), recorder: FakeSystem.recorder, clock: clock)
    }

    func manager() -> StorageManager {
        StorageManager(layout: layout, effects: effects(), sender: server, now: { Self.date })
    }

    /// A loaded manager with the test runtime registered.
    func loadedManager() async throws -> StorageManager {
        let manager = manager()
        _ = try await manager.load()
        try await manager.registerRuntime(runtime)
        return manager
    }

    /// A runtime in another folder, as a runtime update installs it.
    func updatedRuntime(version: String = "1.0.0") -> StorageRuntime {
        StorageRuntime(id: "rustfs-update", version: version, path: directory.path("runtimes/update").path)
    }
}
