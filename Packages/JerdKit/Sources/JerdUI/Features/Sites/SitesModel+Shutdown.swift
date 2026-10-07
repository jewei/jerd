extension SitesModel: ShutdownParticipant {
    public var shutdownPhase: ShutdownPhase { .webEnvironment }

    /// Stops PHP-FPM and Caddy last. A failure keeps Jerd open and shows on this page.
    public func shutdown() async -> Bool {
        isShuttingDown = true
        do {
            try await port.stopEnvironment()
            environment = await port.environment()
            return true
        } catch {
            operation = .failed(message: ErrorText.message(for: error))
            return false
        }
    }

    public func resumeAfterCancelledQuit() {
        isShuttingDown = false
    }
}
