import JerdProcess

/// Watches the processes of one run and reports the first exit once.
///
/// It waits on exit events of the supervisor, without polling.
actor EngineMonitor {
    /// How long one wait lasts before it starts again. Only an exit or a cancellation ends the watch.
    static let waitSlice: Duration = .seconds(3_600)

    private var watchers: [Task<Void, Never>] = []
    private var reported = false

    /// Starts one watcher per token. `onExit` runs once, for the first process that stops running.
    func watch(
        _ tokens: [ProcessToken], processes: any ProcessControlling, onExit: @escaping @Sendable () async -> Void
    ) {
        cancel()
        reported = false
        for token in tokens {
            watchers.append(
                Task {
                    while !Task.isCancelled {
                        let state = await processes.waitForExit(of: token, timeout: Self.waitSlice)
                        guard !Task.isCancelled else { return }
                        if state != .running {
                            await self.report(onExit)
                            return
                        }
                    }
                })
        }
    }

    /// Stops every watcher. No report follows.
    func cancel() {
        reported = true
        for watcher in watchers { watcher.cancel() }
        watchers.removeAll()
    }

    private func report(_ onExit: @Sendable () async -> Void) async {
        guard !reported else { return }
        cancel()
        await onExit()
    }
}
