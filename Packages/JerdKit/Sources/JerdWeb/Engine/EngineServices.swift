import Foundation
import JerdProcess

/// The effects that the serving engine uses. Tests replace single members.
public struct EngineServices: Sendable {
    public var processes: any ProcessControlling
    public var commands: any CommandRunning
    public var pinger: any FPMPinging
    public var ports: LoopbackPortGuard
    public var caBundle: PHPCABundleBuilder
    public var startGate: StartGate
    public var recorder: ActiveRunRecorder
    public var timings: ReadinessTimings

    public init(
        processes: any ProcessControlling = ProcessSupervisor(), commands: any CommandRunning = CommandRunner(),
        pinger: any FPMPinging = FastCGIPing(), ports: LoopbackPortGuard = LoopbackPortGuard(),
        caBundle: PHPCABundleBuilder = PHPCABundleBuilder(), startGate: StartGate = StartGate(),
        recorder: ActiveRunRecorder = ActiveRunRecorder(), timings: ReadinessTimings = ReadinessTimings()
    ) {
        self.processes = processes
        self.commands = commands
        self.pinger = pinger
        self.ports = ports
        self.caBundle = caBundle
        self.startGate = startGate
        self.recorder = recorder
        self.timings = timings
    }

    var readiness: ReadinessChecks {
        ReadinessChecks(commands: commands, pinger: pinger, ports: ports, timings: timings)
    }

    var drift: RuntimeDriftCheck { RuntimeDriftCheck(commands: commands) }
}
