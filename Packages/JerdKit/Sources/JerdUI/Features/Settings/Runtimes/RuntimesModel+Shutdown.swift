extension RuntimesModel: ShutdownParticipant {
    public var shutdownPhase: ShutdownPhase { .runtimeWork }

    /// Cancels the check and an installation that is not activating, then waits for both.
    /// An activation always finishes, so a service is never left half-updated.
    public func shutdown() async -> Bool {
        isShuttingDown = true
        checkTask?.cancel()
        if installation?.canCancel != false {
            installTask?.cancel()
        }
        await installTask?.value
        await checkTask?.value
        return true
    }

    public func resumeAfterCancelledQuit() {
        isShuttingDown = false
    }
}
