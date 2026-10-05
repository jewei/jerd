import Foundation
import JerdDatabases
import JerdFoundation
import JerdProcess
import JerdServiceKit
import os

/// A database manager with fake processes, commands, and `lsof`, in a temporary data folder.
final class DatabaseHarness: Sendable {
    let directory: TemporaryDirectory
    let layout: DatabasesLayout
    let processes = FakeProcessController()
    let lsof: EngineLsof
    let commands: ScriptedCommands
    let initializer: ScriptedCommands
    let system = FakeSystem()
    let runtimes: [DatabaseRuntime]
    private let script = OSAllocatedUnfairLock(initialState: Script())

    struct Script {
        var versionOutput: String?
        var clientOutput: CommandResult?
        var initializerStatus: Int32 = 0
        var initializerOutput = ""
        /// When set, every client probe waits for this gate.
        var clientGate: Gate?
    }

    init() throws {
        let directory = try TemporaryDirectory(" databases ü")
        self.directory = directory
        layout = DataLayout(root: directory.url.appendingPathComponent("Jerd")).databases
        runtimes = DatabaseEngine.allCases.map { engine in
            DatabaseRuntime(
                id: "\(engine.rawValue)-test", engine: engine, version: engine == .postgresql ? "18.6" : "8.4.11",
                path: directory.url.appendingPathComponent("runtimes/\(engine.rawValue)").path)
        }
        let processes = processes
        let lsof = EngineLsof(processes: processes)
        self.lsof = lsof
        let script = script
        let runtimes = runtimes
        commands = ScriptedCommands { request in
            try await Self.answer(request, lsof: lsof, runtimes: runtimes, script: script.withLock { $0 })
        }
        initializer = ScriptedCommands { request in
            let current = script.withLock { $0 }
            if current.initializerStatus == 0, let data = Self.dataFolder(in: request.arguments) {
                try FileManager.default.createDirectory(atPath: data, withIntermediateDirectories: false)
            }
            return CommandResult(status: current.initializerStatus, output: current.initializerOutput)
        }
    }

    deinit { directory.remove() }

    func runtime(_ engine: DatabaseEngine) -> DatabaseRuntime { runtimes.first { $0.engine == engine }! }

    func files(_ id: UUID) -> DatabaseInstanceFiles { DatabaseInstanceFiles(layout: layout.instance(id)) }

    func update(_ change: @Sendable (inout Script) -> Void) { script.withLock { change(&$0) } }

    func effects() -> ServiceEffects {
        let probe = LoopbackProbe(isAccepting: { _ in false }, requireBindable: { _ in })
        return ServiceEffects(
            processes: processes, commands: commands, ports: LoopbackPortGuard(commands: commands, probe: probe),
            startGate: StartGate(observer: system.observer), recorder: FakeSystem.recorder, clock: FakeTimeKeeper())
    }

    func manager() -> DatabaseManager {
        DatabaseManager(layout: layout, effects: effects(), initializationCommands: initializer)
    }

    /// A loaded manager with the three test runtimes.
    func loadedManager() async throws -> DatabaseManager {
        let manager = manager()
        _ = try await manager.load()
        try await manager.registerRuntimes(runtimes)
        return manager
    }

    private static func answer(
        _ request: ProcessRequest, lsof: EngineLsof, runtimes: [DatabaseRuntime], script: Script
    ) async throws -> CommandResult {
        let name = request.executable.lastPathComponent
        if name == "lsof" { return await lsof.answer(request.arguments) }
        if request.arguments == ["--version"] {
            let runtime = runtimes.first { request.executable.path.hasPrefix($0.path) }
            return CommandResult(status: 0, output: script.versionOutput ?? "\(name) Ver \(runtime?.version ?? "?")")
        }
        if let gate = script.clientGate { await gate.wait() }
        if let output = script.clientOutput { return output }
        return CommandResult(status: 0, output: name == "redis-cli" ? "PONG\n" : "42\n")
    }

    private static func dataFolder(in arguments: [String]) -> String? {
        if let value = arguments.first(where: { $0.hasPrefix("--datadir=") }) { return String(value.dropFirst(10)) }
        if let index = arguments.firstIndex(of: "-D") { return arguments[index + 1] }
        return nil
    }
}
