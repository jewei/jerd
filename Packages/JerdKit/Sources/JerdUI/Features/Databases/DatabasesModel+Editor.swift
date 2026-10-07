import Foundation
import JerdDatabases

extension DatabasesModel {
    /// Why Add, Edit, and Remove are off after the user cancelled a sheet whose save still
    /// runs, or nil. The page shows it, because the closed sheet cannot.
    public var cancelledSaveMessage: String? {
        let editorRuns = editorOperation.isWorking && sheet != .editor
        let restoreRuns = restoreOperation.isWorking && sheet != .restore
        return editorRuns || restoreRuns ? CancelledSave.pendingMessage("Add, Edit, and Remove") : nil
    }

    /// Opens the Add sheet for `engine` and asks for a free port.
    public func beginAdd(_ engine: DatabaseEngine) {
        guard canAdd else { return }
        editorOperation = .idle
        editor = .add(engine, in: configuration)
        sheet = .editor
        suggestPort(for: engine)
    }

    /// Opens the Edit sheet of a stopped service.
    public func beginEdit(_ id: UUID) {
        guard canEdit(id), let service = service(id), let runtime = runtime(of: service) else { return }
        editorOperation = .idle
        editor = .edit(service, engine: runtime.engine)
        sheet = .editor
    }

    /// Selects another engine in the Add sheet and asks for its free port.
    public func changeEngine(_ engine: DatabaseEngine) {
        guard editor?.engine != engine else { return }
        editor?.changeEngine(engine, in: configuration)
        suggestPort(for: engine)
    }

    @discardableResult
    func suggestPort(for engine: DatabaseEngine) -> Task<Void, Never> {
        Task {
            guard let port = try? await port.suggestedPort(for: engine) else { return }
            editor?.applySuggestedPort(port, for: engine)
        }
    }

    /// Add registers and starts the service, then selects it. Edit saves the stopped service.
    /// A failure stays in the sheet. After Cancel, the result only refreshes the page.
    @discardableResult
    public func saveEditor() -> Task<Void, Never>? {
        guard let draft = editor, let service = draft.service(in: configuration), canChangeRegistry else { return nil }
        editorOperation = .working(draft.isAdding ? "Creating the database service…" : "Saving the service…")
        let task = track { [self] in
            do {
                let id = try await save(service, adding: draft.isAdding)
                guard !Task.isCancelled else { return endCancelledEditor(failure: nil) }
                editorOperation = .idle
                closeEditor()
                navigate?(.item(.database(id)))
                if draft.isAdding { start(id) }
            } catch {
                await refresh()
                guard !Task.isCancelled else { return endCancelledEditor(failure: error) }
                editorOperation = .failed(message: ErrorText.message(for: error))
            }
        }
        editorTask = task
        return task
    }

    private func endCancelledEditor(failure: (any Error)?) {
        editorOperation = .idle
        editorTask = nil
        if let page = CancelledSave.pageOperation(failure: failure) { operation = page }
    }

    private func save(_ service: DatabaseService, adding: Bool) async throws -> UUID {
        if adding {
            let added = try await port.add(name: service.name, runtimeID: service.runtimeID, port: service.port)
            await refresh()
            return added.id
        }
        try await port.edit(service)
        await refresh()
        return service.id
    }

    /// Closes the sheet. A running save is asked to stop and keeps the registry locked until
    /// it ends, so its late result cannot reach a newer sheet.
    public func closeEditor() {
        editor = nil
        if sheet == .editor { sheet = nil }
        if editorOperation.isWorking {
            editorTask?.cancel()
        } else {
            editorOperation = .idle
        }
    }

    public func requestRemove(_ id: UUID) {
        guard canRemove(id) else { return }
        pendingRemoval = service(id)
    }

    /// Stops the service and removes its registration. Its data stays for Restore.
    @discardableResult
    public func confirmRemove() -> Task<Void, Never>? {
        guard let service = pendingRemoval, canRemove(service.id) else { return nil }
        pendingRemoval = nil
        operation = .working("Stopping \(service.name) and removing its registration…")
        return track { [self] in
            do {
                try await port.remove(service.id)
                await refresh()
                operation = .idle
            } catch {
                await refresh()
                operation = .failed(message: ErrorText.message(for: error))
            }
        }
    }
}
