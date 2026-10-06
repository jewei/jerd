extension TunnelsModel: ShutdownParticipant {
    public var shutdownPhase: ShutdownPhase { .tunnels }

    /// Stops every connector, waits for running edits and stops, then stops again in case a
    /// running Connect started one. A connector that does not stop keeps Jerd open.
    public func shutdown() async -> Bool {
        isShuttingDown = true
        guard isLoaded else { return true }
        do {
            try await port.stopAll()
            await currentWork?.value
            for task in stopWork.values { await task.value }
            try await port.stopAll()
            await refresh()
            return true
        } catch {
            operation = .failed(message: ErrorText.message(for: error))
            await refresh()
            return false
        }
    }

    public func resumeAfterCancelledQuit() {
        isShuttingDown = false
    }
}
