import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdTestSupport
import os

@testable import JerdWeb

/// A ping that passes or fails on request, and counts its calls.
final class FakePinger: FPMPinging {
    private let failing = OSAllocatedUnfairLock(initialState: false)
    private let count = OSAllocatedUnfairLock(initialState: 0)

    var calls: Int { count.withLock { $0 } }
    func fail(_ value: Bool) { failing.withLock { $0 = value } }

    func ping(socket: URL) async throws {
        count.withLock { $0 += 1 }
        if failing.withLock({ $0 }) {
            throw JerdError.processFailed("FPM did not answer its readiness request in time.")
        }
    }
}

/// An engine with fake processes, scripted commands, and a temporary environment.
struct EngineHarness {
    let folder: TemporaryDirectory
    let processes: FakeProcesses
    let pinger = FakePinger()
    let commands: ScriptedCommandRunner
    let engine: EngineRunner
    let environment: EnvironmentLayout
    let listeners: TestListeners

    /// - Parameter failing: an argument that makes its command fail (for example "-t" or "validate").
    init(
        failing: String? = nil, httpsReady: Bool = true, processes: FakeProcesses = FakeProcesses(),
        timings: ReadinessTimings = .fast
    ) throws {
        folder = try TemporaryDirectory(" engine")
        environment = DataLayout(root: folder.url).environment
        listeners = try TestListeners()
        self.processes = processes
        commands = Self.runner(processes: processes, failing: failing, httpsReady: httpsReady)
        let ports = LoopbackPortGuard(
            commands: commands, probe: LoopbackProbe(isAccepting: { _ in false }, requireBindable: { _ in }))
        let services = EngineServices(
            processes: processes, commands: commands, pinger: pinger, ports: ports,
            caBundle: PHPCABundleBuilder(trust: FixedTrust(trusted: false)),
            startGate: StartGate(observer: Self.observer(processes)),
            recorder: ActiveRunRecorder(capture: Self.capture), timings: timings)
        engine = EngineRunner(services: services)
    }

    /// A new layout with a short, not yet existing socket folder and a present test root certificate.
    func layout() throws -> RunLayout {
        let layout = RunLayout(
            environment: environment, socketDirectory: Self.socketFolder(), authority: .isolatedTest)
        try OwnedDirectory.create(layout.rootCertificateFile.deletingLastPathComponent())
        try AtomicFile.write(try Certificates.pem(), to: layout.rootCertificateFile)
        return layout
    }

    var binding: ListenerBinding {
        ListenerBinding(httpsPort: listeners.httpsPort, httpPort: listeners.httpPort, inherited: true)
    }

    /// A plan of real temporary project folders, one per hostname, with the given runtimes.
    func plan(_ hostnames: [String] = ["demo.test"], runtimes: [DevelopmentRuntime]? = nil) throws -> ServingPlan {
        let runtimes = runtimes ?? [Samples.runtime(id: Samples.runtimeID)]
        let sites = try hostnames.enumerated().map { index, host in
            PlannedSite(
                site: Samples.site(try folder.folder("projects/\(host)"), hostname: host),
                runtime: runtimes[index % runtimes.count])
        }
        return ServingPlan(sites: sites, caddy: Samples.caddy())
    }

    func start(_ plan: ServingPlan, layout: RunLayout) async throws -> EngineRunID {
        try await engine.start(plan, layout: layout, binding: binding, listeners: listeners.inherited)
    }

    func remove() {
        listeners.close()
        folder.remove()
    }

    static func socketFolder() -> URL {
        URL(fileURLWithPath: "/tmp/jerd-ut-\(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    private static func runner(processes: FakeProcesses, failing: String?, httpsReady: Bool) -> ScriptedCommandRunner {
        let inspection = InspectionScript()
        return ScriptedCommandRunner { request in
            if let failing, request.arguments.contains(failing) {
                return CommandResult(status: 1, output: "", diagnosticOutput: "\(failing) failed")
            }
            if let answer = inspection.answer(request) { return answer }
            if request.executable.lastPathComponent == "lsof" { return await lsof(request.arguments, processes) }
            if request.executable.lastPathComponent == "curl" {
                return httpsReady
                    ? CommandResult(status: 0, output: "Jerd is ready.")
                    : CommandResult(status: 7, output: "", diagnosticOutput: "curl: (7) not ready")
            }
            return CommandResult(status: 0, output: "")
        }
    }

    /// Caddy lists its two loopback ports; everything else lists nothing.
    private static func lsof(_ arguments: [String], _ processes: FakeProcesses) async -> CommandResult {
        guard arguments.contains("-iTCP"), let index = arguments.firstIndex(of: "-p"),
            let pid = pid_t(arguments[index + 1]), let request = await processes.request(of: pid),
            request.arguments.first == "run"
        else { return CommandResult(status: 1, output: "") }
        let ports = request.listeners.map { try? ListenerPorts.read($0) } ?? nil
        guard let ports else { return CommandResult(status: 1, output: "") }
        return CommandResult(status: 0, output: "p\(pid)\nn127.0.0.1:\(ports.https)\nn127.0.0.1:\(ports.http)\n")
    }

    private static func observer(_ processes: FakeProcesses) -> ProcessObserver {
        ProcessObserver(
            match: { identity in processes.live.withLock { $0.contains(identity.processID) } ? .running : .exited },
            isGone: { pid in !processes.live.withLock { $0.contains(pid) } },
            groups: ProcessGroupInspector(list: { _, _ in (0, 0) }), auditedSignalsSupported: true)
    }

    private static let capture: ActiveRunRecorder.Capture = { pid in
        ProcessIdentity(
            processID: pid, userID: geteuid(), startedSeconds: 1, startedMicroseconds: 0, bootSeconds: 0,
            executable: "/fake", auditWords: [1, 2, 3, 4, 5, 6, 7, 8], bootSessionID: "TEST")
    }
}

extension ReadinessTimings {
    /// Short waits for unit tests.
    static let fast = ReadinessTimings(
        socketWait: .seconds(2), socketPoll: .milliseconds(5), tlsBudget: .seconds(2), tlsPoll: .milliseconds(5),
        requestSeconds: 1, requestTimeout: .seconds(1), validationTimeout: .seconds(1))
}

extension FakeProcesses {
    /// The request of the child with `pid`.
    func request(of pid: pid_t) -> ProcessRequest? {
        children.values.first { $0.pid == pid }?.request
    }
}
