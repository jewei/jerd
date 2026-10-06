import Foundation

extension AdvancedModel {
    /// Asks the user for two trusted executables in turn, then registers them as one PHP runtime.
    @discardableResult
    public func choosePHP() -> Task<Void, Never>? {
        guard isIdle else { return nil }
        return Task {
            guard let cli = await panels.choose(.executable("Select a trusted PHP CLI executable.")),
                let fpm = await panels.choose(.executable("Select the matching PHP-FPM executable."))
            else { return }
            await performAfterPanel("Checking the selected PHP executables…") { model in
                try await model.executables.importPHP(cli: cli, fpm: fpm)
                model.registrations = try await model.executables.registrations()
            }
        }
    }

    /// Asks the user for a trusted Caddy executable, then registers it.
    @discardableResult
    public func chooseCaddy() -> Task<Void, Never>? {
        guard isIdle else { return nil }
        return Task {
            guard let caddy = await panels.choose(.executable("Select a trusted Caddy 2 executable.")) else { return }
            await performAfterPanel("Checking the selected Caddy executable…") { model in
                try await model.executables.importCaddy(caddy)
                model.registrations = try await model.executables.registrations()
            }
        }
    }

    /// Runs a step after an open panel closed. Other work can take the lock while the panel
    /// shows; the page then says so instead of doing nothing.
    private func performAfterPanel(
        _ message: String, _ work: @escaping @MainActor (AdvancedModel) async throws -> Void
    ) async {
        guard let task = perform(message, work) else {
            operation = .failed(message: OperationLock.busyMessage)
            return
        }
        await task.value
    }

    /// One confirmed step, then a refresh of the data that it changed.
    func run(_ step: AdvancedConfirmation) async throws {
        switch step {
        case .recoverProcess(let finding), .clearStaleRecord(let finding):
            // A recovery changes the records whether it succeeds or not, so read them again.
            do {
                try await recovery.recoverProcess(finding.id)
            } catch {
                findings = await recovery.inspectProcesses()
                throw error
            }
            findings = await recovery.inspectProcesses()
        case .deleteBackup(let backup):
            try await recovery.removeBackup(backup.id)
            backups = await recovery.inspectBackups()
        case .removePHP(let runtime):
            try await executables.removePHP(runtime.id)
            registrations = try await executables.registrations()
        case .restoreHTTPS(let status):
            try await https.recover(status, action: .restorePrevious)
            httpsRecovery = try await https.pendingRecovery()
        case .removeHTTPS(let status):
            try await https.recover(status, action: .removeSetup)
            httpsRecovery = try await https.pendingRecovery()
        }
    }

}
