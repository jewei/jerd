extension TunnelsModel: ShutdownParticipant {
    public var shutdownPhase: ShutdownPhase { .tunnels }

    /// The page of the first connector that still runs, where its failure shows; else the
    /// Sites section.
    public var shutdownFailureDestination: Destination {
        guard let tunnel = registrations.first(where: { isActive($0.id) }) else {
            return shutdownPhase.failureDestination
        }
        return .item(.tunnel(tunnel.id))
    }

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
