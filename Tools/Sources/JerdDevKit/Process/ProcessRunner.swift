import Darwin
import Foundation

/// Runs external commands: an absolute executable, an argument array, separate output pipes, and a
/// hard time limit. It never uses a shell. Each child leads its own process group, so the time limit
/// and a forwarded interrupt stop the child and every process that it started.
struct ProcessRunner: ProcessRunning {
    private let output: any TextOutput
    private let killDelay: Duration
    private let drainLimit: Duration
    private let groups: ChildProcessGroups

    /// - Parameters:
    ///   - killDelay: How long a timed-out group has to stop after SIGTERM before it gets SIGKILL.
    ///   - drainLimit: How long to wait for the rest of the output after the child exits. A grandchild
    ///     that keeps a pipe open must not block the tool.
    ///   - groups: Where the running process groups are registered for the signal forwarder.
    init(
        output: any TextOutput,
        killDelay: Duration = .seconds(5),
        drainLimit: Duration = .seconds(2),
        groups: ChildProcessGroups = .shared
    ) {
        self.output = output
        self.killDelay = killDelay
        self.drainLimit = drainLimit
        self.groups = groups
    }

    func run(_ invocation: Invocation, output mode: OutputMode) async throws -> InvocationResult {
        let (events, continuation) = AsyncStream.makeStream(of: ProcessRunState.Event.self)
        let standardOutput = OutputCollector(channel: .standardOutput, mode: mode, output: output)
        let standardError = OutputCollector(channel: .standardError, mode: mode, output: output)
        let pipes = [
            attachPipe(.standardOutput, to: standardOutput, continuation: continuation),
            attachPipe(.standardError, to: standardError, continuation: continuation),
        ]
        defer {
            pipes.forEach { $0.fileHandleForReading.readabilityHandler = nil }
            continuation.finish()
        }
        let group = try start(invocation, pipes: pipes)
        ChildProcess.waitForExit(group) { continuation.yield(.exited(status: $0)) }
        let outcome = await drive(group: group, events: events, continuation: continuation, timeout: invocation.timeout)
        groups.finish(group) { ChildProcess.reap(group) }
        standardOutput.finish()
        standardError.finish()
        var result = InvocationResult(
            commandLine: invocation.commandLine, status: 0,
            standardOutput: standardOutput.text, standardError: standardError.text)
        switch outcome {
        case .exited(let status):
            result.status = status
        case .timedOut(let status):
            result.status = status
            result.exceededTimeLimit = invocation.timeout
        }
        return result
    }

    /// Starts the child with the write ends of the pipes, then closes them here, so that the pipes
    /// close when the last process of the group closes them.
    private func start(_ invocation: Invocation, pipes: [Pipe]) throws -> pid_t {
        let outputDescriptor = pipes[0].fileHandleForWriting.fileDescriptor
        let errorDescriptor = pipes[1].fileHandleForWriting.fileDescriptor
        defer { pipes.forEach { try? $0.fileHandleForWriting.close() } }
        return try groups.start(commandLine: invocation.commandLine) {
            try ChildProcess.spawn(invocation, standardOutput: outputDescriptor, standardError: errorDescriptor)
        }
    }

    private func attachPipe(
        _ channel: OutputChannel,
        to collector: OutputCollector,
        continuation: AsyncStream<ProcessRunState.Event>.Continuation
    ) -> Pipe {
        let pipe = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.yield(.outputClosed(channel))
            } else {
                collector.append(data)
            }
        }
        return pipe
    }

    /// Feeds events to the state machine and performs its actions until it finishes.
    private func drive(
        group: pid_t,
        events: AsyncStream<ProcessRunState.Event>,
        continuation: AsyncStream<ProcessRunState.Event>.Continuation,
        timeout: Duration
    ) async -> ProcessRunState.Outcome {
        var state = ProcessRunState()
        var timers = [Self.timer(after: timeout, event: .timeLimitReached, continuation: continuation)]
        defer { timers.forEach { $0.cancel() } }
        for await event in events {
            for action in state.handle(event) {
                switch action {
                case .terminate:
                    ChildProcess.signalGroup(group, SIGTERM)
                    timers.append(Self.timer(after: killDelay, event: .killDelayReached, continuation: continuation))
                case .kill:
                    ChildProcess.signalGroup(group, SIGKILL)
                case .startDrainTimer:
                    timers.append(Self.timer(after: drainLimit, event: .drainLimitReached, continuation: continuation))
                case .finish(let outcome):
                    return outcome
                }
            }
        }
        return .timedOut(status: -1)
    }

    private static func timer(
        after delay: Duration,
        event: ProcessRunState.Event,
        continuation: AsyncStream<ProcessRunState.Event>.Continuation
    ) -> Task<Void, Never> {
        Task {
            do {
                try await Task.sleep(for: delay)
                continuation.yield(event)
            } catch {
                // Cancelled: the process finished first, so the event is not needed.
            }
        }
    }
}
