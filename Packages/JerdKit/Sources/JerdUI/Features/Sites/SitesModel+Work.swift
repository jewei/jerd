extension SitesModel {
    /// Starts site work under the shared lock. The operation shows its message at once; `body`
    /// sets the final state. The quit may cancel stoppable work: the cancellation then asks
    /// the port to stop the change at its next step.
    /// - Returns: The task, or nil when a change cannot start now.
    @discardableResult
    func startWork(
        _ message: String, canStop: Bool = false, _ body: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never>? {
        guard canChange else { return nil }
        let port = port
        let task = lock.run(message, canCancel: canStop) { [self] in
            await withTaskCancellationHandler {
                await body()
            } onCancel: {
                Task { await port.requestStop() }
            }
            await settle()
        }
        guard let task else { return nil }
        operation = .working(message: message, canStop: canStop)
        currentWork = task
        return task
    }

    /// Runs one site operation with its banner message, then reads the state again. A Stop
    /// ends the operation without an error. Other failures show once, on this page.
    /// - Parameter canStop: True when Stop All Sites can end the operation at its next step.
    @discardableResult
    func perform(
        _ message: String, canStop: Bool = false, _ work: @escaping @MainActor (SitesModel) async throws -> Void
    ) -> Task<Void, Never>? {
        startWork(message, canStop: canStop) { [self] in
            do {
                try await work(self)
                operation = .idle
            } catch is CancellationError {
                operation = .idle
            } catch {
                operation = .failed(message: ErrorText.message(for: error))
            }
        }
    }
}
