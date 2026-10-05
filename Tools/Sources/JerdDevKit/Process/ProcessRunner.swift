import Foundation

/// Runs external commands with Foundation `Process`: an absolute executable, an argument array,
/// separate output pipes, and a hard time limit. It never uses a shell.
public struct ProcessRunner: ProcessRunning {
    private let output: any TextOutput
    private let killDelay: Duration
    private let drainLimit: Duration

    /// - Parameters:
    ///   - killDelay: How long a timed-out child has to stop after SIGTERM before it gets SIGKILL.
    ///   - drainLimit: How long to wait for the rest of the output after the child exits. A grandchild
    ///     that keeps a pipe open must not block the tool.
    public init(output: any TextOutput, killDelay: Duration = .seconds(5), drainLimit: Duration = .seconds(2)) {
        self.output = output
        self.killDelay = killDelay
        self.drainLimit = drainLimit
    }

    public func run(_ invocation: Invocation, output mode: OutputMode) async throws -> InvocationResult {
        let (events, continuation) = AsyncStream.makeStream(of: ProcessRunState.Event.self)
        let standardOutput = OutputCollector(channel: .standardOutput, mode: mode, output: output)
        let standardError = OutputCollector(channel: .standardError, mode: mode, output: output)
        let process = makeProcess(for: invocation)
        let pipes = [
            attachPipe(.standardOutput, to: standardOutput, continuation: continuation),
            attachPipe(.standardError, to: standardError, continuation: continuation),
        ]
        process.standardOutput = pipes[0]
        process.standardError = pipes[1]
        process.terminationHandler = { finished in
            continuation.yield(.exited(status: Self.shellStyleStatus(of: finished)))
        }
        defer {
            pipes.forEach { $0.fileHandleForReading.readabilityHandler = nil }
            continuation.finish()
        }
        do {
            try process.run()
        } catch {
            throw InvocationFailure.launchFailed(
                commandLine: invocation.commandLine, reason: error.localizedDescription)
        }
        let outcome = await drive(process, events: events, continuation: continuation, timeout: invocation.timeout)
        standardOutput.finish()
        standardError.finish()
        switch outcome {
        case .timedOut:
            throw InvocationFailure.timedOut(commandLine: invocation.commandLine, limit: invocation.timeout)
        case .exited(let status):
            return InvocationResult(
                commandLine: invocation.commandLine, status: status,
                standardOutput: standardOutput.text, standardError: standardError.text)
        }
    }

    private func makeProcess(for invocation: Invocation) -> Process {
        let process = Process()
        process.executableURL = invocation.executable
        process.arguments = invocation.arguments
        process.standardInput = FileHandle.nullDevice
        if let environment = invocation.environment {
            process.environment = environment
        }
        if let workingDirectory = invocation.workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        return process
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
        _ process: Process,
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
                    process.terminate()
                    timers.append(Self.timer(after: killDelay, event: .killDelayReached, continuation: continuation))
                case .kill:
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                case .startDrainTimer:
                    timers.append(Self.timer(after: drainLimit, event: .drainLimitReached, continuation: continuation))
                case .finish(let outcome):
                    return outcome
                }
            }
        }
        return .timedOut
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

    /// The exit status as a shell reports it: 128 plus the signal number for a signal.
    private static func shellStyleStatus(of process: Process) -> Int32 {
        process.terminationReason == .uncaughtSignal ? 128 + process.terminationStatus : process.terminationStatus
    }
}
