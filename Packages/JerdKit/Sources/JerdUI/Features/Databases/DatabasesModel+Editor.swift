import Foundation
import JerdDatabases

extension DatabasesModel {
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
    /// A failure stays in the sheet.
    @discardableResult
    public func saveEditor() -> Task<Void, Never>? {
        guard let draft = editor, let service = draft.service(in: configuration), canChangeRegistry else { return nil }
        editorOperation = .working(draft.isAdding ? "Creating the database service…" : "Saving the service…")
        return track(
            Task {
                do {
                    let id = try await save(service, adding: draft.isAdding)
                    closeEditor()
                    navigate?(.item(.database(id)))
                    if draft.isAdding { start(id) }
                } catch {
                    await refresh()
                    editorOperation = .failed(message: ErrorText.message(for: error))
                }
            })
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

    /// Closes the sheet. A save in progress finishes; only the wait ends.
    public func closeEditor() {
        editor = nil
        editorOperation = .idle
        if sheet == .editor { sheet = nil }
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
        return track(
            Task {
                do {
                    try await port.remove(service.id)
                    await refresh()
                    operation = .idle
                } catch {
                    await refresh()
                    operation = .failed(message: ErrorText.message(for: error))
                }
            })
    }
}
