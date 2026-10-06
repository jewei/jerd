import Foundation
import JerdDatabases

extension DatabasesModel {
    @discardableResult
    public func start(_ id: UUID) -> Task<Void, Never>? {
        guard canStart(id) else { return nil }
        return control(id) { try await $0.port.start(id) }
    }

    /// Stops a service, or tries again to stop one that did not stop.
    @discardableResult
    public func stop(_ id: UUID) -> Task<Void, Never>? {
        guard canStop(id) else { return nil }
        return control(id) { try await $0.port.stop(id) }
    }

    /// Runs a start or stop of one service. The service state shows its own failure; any other
    /// failure shows once, as the page banner.
    private func control(
        _ id: UUID, _ work: @escaping @MainActor (DatabasesModel) async throws -> Void
    ) -> Task<Void, Never> {
        busyServices.insert(id)
        if operation.failureMessage != nil { operation = .idle }
        return track { [self] in
            var failure: String?
            do {
                try await work(self)
            } catch {
                failure = ErrorText.message(for: error)
            }
            await refresh()
            busyServices.remove(id)
            if let failure, !state(of: id).needsAttention { operation = .failed(message: failure) }
        }
    }

    @discardableResult
    public func copyPassword(_ id: UUID) -> Task<Void, Never> {
        copyConnection(id, confirmation: "Copied password") { $0.password }
    }

    @discardableResult
    public func copyEnvironment(_ id: UUID) -> Task<Void, Never> {
        copyConnection(id, confirmation: "Copied Laravel settings") { $0.environment }
    }

    public func copyValue(_ value: String, label: String) {
        clipboard.copy(value, confirmation: "Copied \(label.lowercased())")
    }

    public func revealData(_ id: UUID) {
        guard let files = files[id], files.hasDataFolder else { return }
        workspace.reveal(files.dataFolder)
    }

    public func openLog(_ id: UUID) {
        guard let files = files[id], files.hasLog else { return }
        workspace.open(files.log)
    }

    public func showRuntimes() {
        navigate?(.dashboard(.runtimes))
    }

    /// Reads the connection and copies one value. It runs beside other work. When the user
    /// selected another service during the read, the value is dropped, so the pasteboard never
    /// gets the password of a service that the page no longer shows.
    private func copyConnection(
        _ id: UUID, confirmation: String, _ value: @escaping @Sendable (DatabaseConnection) -> String
    ) -> Task<Void, Never> {
        Task {
            do {
                let connection = try await port.connection(for: id)
                guard isSelected(id) else { return }
                clipboard.copy(value(connection), confirmation: confirmation)
            } catch {
                guard isSelected(id), !operation.isWorking else { return }
                operation = .failed(message: ErrorText.message(for: error))
            }
        }
    }

    /// True when the page shows `id`, or when no page reports a selection.
    private func isSelected(_ id: UUID) -> Bool {
        guard let selectedService else { return true }
        return selectedService() == id
    }
}
