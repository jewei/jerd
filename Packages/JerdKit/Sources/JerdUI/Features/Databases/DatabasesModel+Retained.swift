import Foundation
import JerdDatabases

extension DatabasesModel {
    /// Opens the Retained Databases sheet and inspects the data folders.
    public func showRetained() {
        guard loadState.isLoaded, !isShuttingDown else { return }
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

    /// Registers the retained data again and selects it. A failure stays in the sheet.
    @discardableResult
    public func saveRestore() -> Task<Void, Never>? {
        guard let draft = restoreDraft, let values = draft.values(in: configuration), canChangeRegistry else {
            return nil
        }
        restoreOperation = .working("Restoring the registration…")
        return track(
            Task {
                do {
                    let service = try await port.restoreRegistration(
                        draft.database.id, name: values.name, port: values.port)
                    await refresh()
                    closeRestore()
                    retained.removeAll { $0.id == service.id }
                    navigate?(.item(.database(service.id)))
                } catch {
                    restoreOperation = .failed(message: ErrorText.message(for: error))
                }
            })
    }

    public func closeRestore() {
        restoreDraft = nil
        restoreOperation = .idle
        if sheet == .restore { sheet = nil }
    }

    public func closeRetained() {
        retainedOperation = .idle
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
