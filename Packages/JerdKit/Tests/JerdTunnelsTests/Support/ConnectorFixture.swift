import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdTestSupport
import JerdTunnels

/// A `CloudflaredConnector` in a temporary data root, with fake processes, fake commands, and a fake
/// executable file named `cloudflared` that is never run.
struct ConnectorFixture {
    let folder: TemporaryDirectory
    let processes = FakeProcessController()
    let commands = RecordingCommandRunner()
    let portCommands = RecordingCommandRunner(RecordingCommandRunner.freePorts)
    let connector: CloudflaredConnector
    let runtime: TunnelRuntime
    let registration = TunnelRegistration(name: "Preview", hostname: "preview.example.com")

    init(capture: @escaping ActiveRunRecorder.Capture = ConnectorFixture.fakeIdentity) throws {
        folder = try TemporaryDirectory(" tunnels")
        let runtimeFolder = folder.url.appendingPathComponent("runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeFolder, withIntermediateDirectories: true)
        let executable = runtimeFolder.appendingPathComponent("cloudflared")
        try Data("not a real program".utf8).write(to: executable)
        chmod(executable.path, 0o700)
        runtime = TunnelRuntime(version: "2026.9.3", directory: runtimeFolder)
        let ports = LoopbackPortGuard(
            commands: portCommands, probe: LoopbackProbe(isAccepting: { _ in false }, requireBindable: { _ in }))
        connector = CloudflaredConnector(
            layout: folder.layout, processes: processes, commands: commands, ports: ports,
            recorder: ActiveRunRecorder(capture: capture))
    }

    var instance: TunnelInstanceLayout { folder.layout.instance(registration.id) }

    func launch(token: String = TokenSamples.valid) throws -> TunnelLaunch {
        TunnelLaunch(runtime: runtime, registration: registration, token: try TunnelToken(token))
    }

    /// True when another owner could take the instance lock now.
    func lockIsFree() -> Bool {
        let lock = try? InstanceLock.acquire(
            at: instance.lockFile, messages: InstanceLock.Messages(unavailable: "Unavailable.", busy: "Busy."))
        lock?.release()
        return lock != nil
    }

    /// An identity for a fake PID, owned by the current user.
    static func fakeIdentity(_ processID: pid_t) -> ProcessIdentity {
        ProcessIdentity(
            processID: processID, userID: geteuid(), startedSeconds: 1, startedMicroseconds: 0, bootSeconds: 1,
            executable: "/fake/cloudflared", auditWords: nil, bootSessionID: nil)
    }
}
