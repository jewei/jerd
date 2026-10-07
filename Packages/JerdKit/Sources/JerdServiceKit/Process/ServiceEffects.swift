import JerdProcess

/// The side-effect ports of managed instances. One value is shared by every instance of the app,
/// so that one supervisor owns every service process.
public struct ServiceEffects: Sendable {
    /// The graceful stop limit of data services.
    public static let defaultStopTimeout: Duration = .seconds(30)

    public var processes: any ProcessControlling
    public var commands: any CommandRunning
    public var ports: LoopbackPortGuard
    public var startGate: StartGate
    public var recorder: ActiveRunRecorder
    public var clock: any TimeKeeping
    /// How long a graceful stop waits. A timeout never sends `SIGKILL`.
    public var stopTimeout: Duration

    public init(
        processes: any ProcessControlling, commands: any CommandRunning = CommandRunner(),
        ports: LoopbackPortGuard = LoopbackPortGuard(), startGate: StartGate = StartGate(),
        recorder: ActiveRunRecorder = ActiveRunRecorder(), clock: any TimeKeeping = SystemTimeKeeper(),
        stopTimeout: Duration = defaultStopTimeout
    ) {
        self.processes = processes
        self.commands = commands
        self.ports = ports
        self.startGate = startGate
        self.recorder = recorder
        self.clock = clock
        self.stopTimeout = stopTimeout
    }

    /// The graceful policy for `signal`. It never escalates to `SIGKILL`.
    public func stopPolicy(signal: Int32) -> StopPolicy {
        .graceful(signal: signal, timeout: stopTimeout)
    }
}
