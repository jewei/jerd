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

    /// Opens the Add sheet for `engine` and asks for a free port. An engine without a runtime
    /// opens too: the sheet installs its pinned runtime first.
    public func beginAdd(_ engine: DatabaseEngine) {
        guard canAdd, addableEngines.contains(engine) else { return }
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

    /// The pinned runtime that Add installs first: the draft's engine has no runtime yet.
    public var editorRuntimeOffer: DatabaseRuntimeOffer? {
        guard let draft = editor, draft.isAdding, draft.runtimeID == nil else { return nil }
        return offer(for: draft.engine)
    }

    /// True when the sheet can save now. Add of an engine without a runtime also needs the
    /// installer, which runs one installation at a time.
    public var canSaveEditor: Bool {
        guard let draft = editor, canChangeRegistry else { return false }
        guard editorRuntimeOffer != nil else { return draft.service(in: configuration) != nil }
        return runtimeInstallation == nil && runtimeInstallElsewhere?() == nil
            && draft.issue(in: configuration, installsRuntime: true) == nil
            && PortInput.parse(draft.portText) != nil
    }

    /// Add registers and starts the service, then selects it; for an engine without a runtime,
    /// it installs the pinned runtime first, in the same sheet. Edit saves the stopped service.
    /// A failure stays in the sheet. After Cancel, the result only refreshes the page.
    @discardableResult
    public func saveEditor() -> Task<Void, Never>? {
        guard canSaveEditor, let draft = editor else { return nil }
        let offer = editorRuntimeOffer
        editorOperation = .working(
            offer.map { "Installing \($0.engine.title)…" }
                ?? (draft.isAdding ? "Creating the database service…" : "Saving the service…"))
        let task = track { [self] in
            do {
                // The draft as Save saw it: Cancel clears the sheet's draft while the save runs.
                var saved = draft
                if let offer {
                    let runtime = try await installRuntime(offer, addsService: true)
                    guard !Task.isCancelled else { return endCancelledEditor(failure: nil) }
                    saved.runtimeID = runtime.id
                    editor?.runtimeID = runtime.id
                    editorOperation = .working("Creating the database service…")
                }
                guard let service = saved.service(in: configuration) else { return endCancelledEditor(failure: nil) }
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
