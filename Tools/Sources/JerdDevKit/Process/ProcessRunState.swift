/// The life of one child process as a pure state machine. `ProcessRunner` feeds it events and performs
/// the actions that it returns, so every timing rule has a unit test without a real process.
struct ProcessRunState: Equatable {
    enum Event: Equatable {
        case exited(status: Int32)
        case outputClosed(OutputChannel)
        case timeLimitReached
        case killDelayReached
        case drainLimitReached
    }

    enum Action: Equatable {
        /// Send SIGTERM and start the kill delay.
        case terminate
        /// Send SIGKILL: the child ignored SIGTERM.
        case kill
        /// The child exited but a grandchild may keep a pipe open. Wait a short time for the rest of the output.
        case startDrainTimer
        case finish(Outcome)
    }

    enum Outcome: Equatable {
        case exited(status: Int32)
        case timedOut
    }

    private(set) var exitStatus: Int32?
    private(set) var timedOut = false
    private(set) var openChannels: Set<OutputChannel> = [.standardOutput, .standardError]
    private(set) var isFinished = false

    mutating func handle(_ event: Event) -> [Action] {
        guard !isFinished else { return [] }
        switch event {
        case .exited(let status):
            exitStatus = status
            return openChannels.isEmpty ? [finish()] : [.startDrainTimer]
        case .outputClosed(let channel):
            openChannels.remove(channel)
            return exitStatus != nil && openChannels.isEmpty ? [finish()] : []
        case .timeLimitReached:
            guard exitStatus == nil, !timedOut else { return [] }
            timedOut = true
            return [.terminate]
        case .killDelayReached:
            return exitStatus == nil ? [.kill] : []
        case .drainLimitReached:
            return exitStatus != nil ? [finish()] : []
        }
    }

    private mutating func finish() -> Action {
        isFinished = true
        if timedOut { return .finish(.timedOut) }
        return .finish(.exited(status: exitStatus ?? -1))
    }
}
