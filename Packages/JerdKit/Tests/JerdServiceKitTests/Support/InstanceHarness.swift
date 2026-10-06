import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import os

/// A managed instance with fake processes, fake `lsof`, a fake clock, and a temporary folder.
final class InstanceHarness: Sendable {
    static let secret = "s3cr3t-password-value"

    let directory: TemporaryDirectory
    let processes = FakeProcessController()
    let lsof: FakeLsof
    let commands: ScriptedCommands
    let clock = FakeTimeKeeper()
    let events = EventLog()
    let system = FakeSystem()
    let probe = ProbeScript()
    let ports: [UInt16]
    let id = UUID()
    private let version = OSAllocatedUnfairLock(initialState: "server 1.2.3")

    init(ports: [UInt16] = [41_001]) throws {
        directory = try TemporaryDirectory()
        self.ports = ports
        lsof = FakeLsof(processes: processes, servicePorts: Set(ports))
        let version = version
        commands = ScriptedCommands { [lsof] request in
            if request.executable.lastPathComponent == "lsof" { return await lsof.answer(request.arguments) }
            guard request.arguments == ["--version"] else { return CommandResult(status: 1, output: "") }
            return CommandResult(status: 0, output: version.withLock { $0 })
        }
        try OwnedDirectory.create(area)
    }

    deinit { directory.remove() }

    /// The existing folder that contains the instance folder.
    var area: URL { directory.url.appendingPathComponent("services", isDirectory: true) }
    var folder: URL { area.appendingPathComponent(id.uuidString, isDirectory: true) }
    var lockFile: URL { folder.appendingPathComponent("service.lock") }
    var recordFile: URL { folder.appendingPathComponent("active-run.json") }
    var logFile: URL { folder.appendingPathComponent("server.log") }
    var socketFolder: URL { folder.appendingPathComponent("sockets", isDirectory: true) }
    var record: RecordLocation {
        RecordLocation(family: .database, instance: id, recordFile: recordFile, lockFile: lockFile)
    }

    func setVersionOutput(_ text: String) { version.withLock { $0 = text } }

    func effects(stopTimeout: Duration = .seconds(30)) -> ServiceEffects {
        let probe = LoopbackProbe(isAccepting: { _ in false }, requireBindable: { _ in })
        return ServiceEffects(
            processes: processes, commands: commands, ports: LoopbackPortGuard(commands: commands, probe: probe),
            startGate: StartGate(observer: system.observer), recorder: FakeSystem.recorder, clock: clock,
            stopTimeout: stopTimeout)
    }

    func definition(
        name: String = "Fake service", stopSignal: Int32 = SIGTERM, detail: ReadinessCheck.TimeoutDetail = .lastFailure,
        setup: Bool = false
    ) -> FakeServiceDefinition {
        let log = ServiceLog(file: logFile, previousFile: folder.appendingPathComponent("server.previous.log"))
        let profile = ServiceProfile(
            name: name, runtimeID: "fake-1.2.3", record: record, containingDirectory: area, log: log, ports: ports,
            stopSignal: stopSignal, messages: FakeServiceDefinition.messages)
        let server = URL(fileURLWithPath: "/fake/bin/server")
        let versionProbe = VersionProbe(
            request: ProcessRequest(executable: server, arguments: ["--version"], workingDirectory: folder),
            rule: .standalone(version: "1.2.3"), mismatchMessage: "The fake server version does not match.")
        return FakeServiceDefinition(
            profile: profile, versionProbe: versionProbe, plan: plan(arguments: ["--serve"], ports: Set(ports), detail),
            setupPlan: setup ? plan(arguments: ["--setup"], ports: [], detail) : nil, events: events)
    }

    func instance(_ definition: FakeServiceDefinition? = nil, stopTimeout: Duration = .seconds(30)) -> ManagedInstance {
        ManagedInstance(definition: definition ?? self.definition(), effects: effects(stopTimeout: stopTimeout))
    }

    private func plan(arguments: [String], ports: Set<UInt16>, _ detail: ReadinessCheck.TimeoutDetail) -> LaunchPlan {
        let probe = probe
        let readiness = ReadinessCheck(
            deadline: .seconds(45), interval: .milliseconds(100), initialFailure: "No answer.",
            timeoutMessage: "The fake service timed out.", timeoutDetail: detail, probe: { try await probe.next() })
        return LaunchPlan(
            request: ProcessRequest(
                executable: URL(fileURLWithPath: "/fake/bin/server"), arguments: arguments, workingDirectory: folder),
            ports: ports, readiness: readiness, secrets: [Self.secret], temporaryItems: [socketFolder])
    }
}
