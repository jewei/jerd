import Darwin
import Foundation
import JerdFoundation
import JerdMail
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import os

/// A mail manager with fake processes, commands, `lsof`, and Mailpit answers, in a temporary
/// data folder.
final class MailHarness: Sendable {
    struct Script {
        /// The version that every fake `mailpit` prints after its own path.
        var version = "1.31.3"
        /// Replaces the whole version output.
        var versionOutput: String?
        var sendResult = CommandResult(status: 0, output: "")
        /// The bytes and mode of the last uploaded message file, read while `curl` ran.
        var uploaded: (data: Data, mode: mode_t)?
    }

    let directory: TemporaryDirectory
    let layout: DataLayout
    let processes = FakeProcessController()
    let lsof: MailLsof
    let commands: ScriptedCommands
    let server = FakeMailServer()
    let system = FakeSystem()
    let clock = FakeTimeKeeper()
    let runtime: MailRuntime
    private let script = OSAllocatedUnfairLock(initialState: Script())

    init() throws {
        let directory = try TemporaryDirectory()
        self.directory = directory
        layout = DataLayout(root: directory.path("Jerd"))
        try OwnedDirectory.create(layout.root)
        runtime = MailRuntime(
            id: "mailpit-1.31.3-arm64", version: "1.31.3", path: directory.path("runtimes/mailpit-1.31.3").path)
        let lsof = MailLsof(processes: processes)
        self.lsof = lsof
        let script = script
        commands = ScriptedCommands { request in
            switch request.executable.lastPathComponent {
            case "lsof": return await lsof.answer(request.arguments)
            case "mailpit":
                let current = script.withLock { $0 }
                let output =
                    current.versionOutput
                    ?? "\(request.executable.path) v\(current.version) compiled with go on darwin\n"
                return CommandResult(status: 0, output: output)
            default: return Self.curl(request, script: script)
            }
        }
        server.serve(database: layout.mail.inboxDatabaseFile)
    }

    deinit { directory.remove() }

    var mail: MailLayout { layout.mail }

    func update(_ change: @Sendable (inout Script) -> Void) { script.withLock { change(&$0) } }

    var uploaded: (data: Data, mode: mode_t)? { script.withLock { $0.uploaded } }

    func effects(stopTimeout: Duration = .seconds(30)) -> ServiceEffects {
        let probe = LoopbackProbe(isAccepting: { _ in false }, requireBindable: { _ in })
        return ServiceEffects(
            processes: processes, commands: commands, ports: LoopbackPortGuard(commands: commands, probe: probe),
            startGate: StartGate(observer: system.observer), recorder: FakeSystem.recorder, clock: clock,
            stopTimeout: stopTimeout)
    }

    func manager() -> MailManager {
        MailManager(layout: layout, effects: effects(), server: server)
    }

    /// A loaded manager with the test runtime registered.
    func loadedManager() async throws -> MailManager {
        let manager = manager()
        _ = try await manager.load()
        try await manager.registerRuntime(runtime)
        return manager
    }

    /// A runtime in another folder with the same version, as a runtime update installs it.
    func updatedRuntime(version: String = "1.31.3") -> MailRuntime {
        MailRuntime(id: "mailpit-update", version: version, path: directory.path("runtimes/update").path)
    }

    private static func curl(_ request: ProcessRequest, script: OSAllocatedUnfairLock<Script>) -> CommandResult {
        guard let index = request.arguments.firstIndex(of: "--upload-file") else {
            return CommandResult(status: 0, output: "250 2.0.0 Ok\r\n")
        }
        let file = request.arguments[index + 1]
        var info = stat()
        let data = (try? Data(contentsOf: URL(fileURLWithPath: file))) ?? Data()
        let mode = lstat(file, &info) == 0 ? info.st_mode & 0o777 : 0
        return script.withLock {
            $0.uploaded = (data, mode)
            return $0.sendResult
        }
    }
}
