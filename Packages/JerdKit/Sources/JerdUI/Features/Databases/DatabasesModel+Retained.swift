import Foundation
import JerdDatabases

extension DatabasesModel {
    /// True when the Retained Databases sheet can open: the registry is loaded and no quit runs.
    public var canShowRetained: Bool { loadState.isLoaded && !isShuttingDown }

    /// Opens the Retained Databases sheet and inspects the data folders.
    public func showRetained() {
        guard canShowRetained else { return }
        sheet = .retained
        inspectRetained()
    }

    @discardableResult
    public func inspectRetained() -> Task<Void, Never>? {
        guard !retainedOperation.isWorking else { return nil }
        retainedOperation = .working("Inspecting data folders…")
        return Task {
            do {
                retained = try await port.retainedDatabases()
                retainedOperation = .idle
            } catch {
                retainedOperation = .failed(message: ErrorText.message(for: error))
            }
        }
    }

    /// Hands the retained list over to the restore editor of one folder.
    public func beginRestore(_ database: RetainedDatabase) {
        guard database.canRestore, canChangeRegistry else { return }
        restoreOperation = .idle
        restoreDraft = RestoreDraft(database: database)
        sheet = .restore
        guard database.port == nil, let engine = database.runtime?.engine else { return }
        Task {
            guard let port = try? await port.suggestedPort(for: engine), restoreDraft?.portText.isEmpty == true
            else { return }
            restoreDraft?.portText = String(port)
        }
    }

    /// Registers the retained data again and selects it. A failure stays in the sheet. After
    /// Cancel, the result only refreshes the page.
    @discardableResult
    public func saveRestore() -> Task<Void, Never>? {
        guard let draft = restoreDraft, let values = draft.values(in: configuration), canChangeRegistry else {
            return nil
        }
        restoreOperation = .working("Restoring the registration…")
        let task = track { [self] in
            do {
                let service = try await port.restoreRegistration(
                    draft.database.id, name: values.name, port: values.port)
                await refresh()
                retained.removeAll { $0.id == service.id }
                guard !Task.isCancelled else { return endCancelledRestore(failure: nil) }
                restoreOperation = .idle
                closeRestore()
                navigate?(.item(.database(service.id)))
            } catch {
                guard !Task.isCancelled else { return endCancelledRestore(failure: error) }
                restoreOperation = .failed(message: ErrorText.message(for: error))
            }
        }
        restoreTask = task
        return task
    }

    private func endCancelledRestore(failure: (any Error)?) {
        restoreOperation = .idle
        restoreTask = nil
        if let page = CancelledSave.pageOperation(failure: failure) { operation = page }
    }

    /// Closes the restore sheet, with the same rule as `closeEditor()`.
    public func closeRestore() {
        restoreDraft = nil
        if sheet == .restore { sheet = nil }
        if restoreOperation.isWorking {
            restoreTask?.cancel()
        } else {
            restoreOperation = .idle
        }
    }

    /// Closes the retained list. An inspection in progress finishes and fills the list.
    public func closeRetained() {
        if retainedOperation.failureMessage != nil { retainedOperation = .idle }
        if sheet == .retained { sheet = nil }
    }

    /// Closes whichever sheet shows.
    public func dismissSheet() {
        switch sheet {
        case .editor: closeEditor()
        case .retained: closeRetained()
        case .restore: closeRestore()
        case nil: break
        }
    }
}

extension DatabasesModel {
    /// Shows a retained data folder in Finder.
    public func revealRetained(_ database: RetainedDatabase) {
        workspace.reveal(database.directory)
    }
}
