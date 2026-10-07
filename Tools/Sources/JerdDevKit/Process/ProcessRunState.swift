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
        /// Send SIGTERM to the child's process group and start the kill delay.
        case terminate
        /// Send SIGKILL to the child's process group: a process in it ignored SIGTERM.
        case kill
        /// The child exited but a grandchild may keep a pipe open. Wait a short time for the rest of the output.
        case startDrainTimer
        case finish(Outcome)
    }

    enum Outcome: Equatable {
        case exited(status: Int32)
        /// The child passed its time limit. The status is how it ended after the signals.
        case timedOut(status: Int32)
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
            return openChannels.isEmpty ? finish() : [.startDrainTimer]
        case .outputClosed(let channel):
            openChannels.remove(channel)
            return exitStatus != nil && openChannels.isEmpty ? finish() : []
        case .timeLimitReached:
            guard exitStatus == nil, !timedOut else { return [] }
            timedOut = true
            return [.terminate]
        case .killDelayReached:
            return exitStatus == nil ? [.kill] : []
        case .drainLimitReached:
            return exitStatus != nil ? finish() : []
        }
    }

    /// After a time-out, SIGKILL also reaches every process that is left in the group, for example a
    /// grandchild that ignored SIGTERM after the child itself stopped.
    private mutating func finish() -> [Action] {
        isFinished = true
        let status = exitStatus ?? -1
        return timedOut ? [.kill, .finish(.timedOut(status: status))] : [.finish(.exited(status: status))]
    }
}
