import Foundation
import JerdDatabases

extension DatabaseDraft {
    /// The first rule that the fields break, as the inline message, or nil. The port must be
    /// free among the registered services; the manager checks the system listeners on Save.
    public func issue(in configuration: DatabaseConfiguration) -> String? {
        guard runtimeID != nil else { return "Install a \(engine.title) runtime in Runtimes first." }
        let trimmed = DatabaseConfiguration.trimmed(name)
        if trimmed.isEmpty { return "Enter a name." }
        guard DatabaseConfiguration.isValidName(name) else {
            return "Use a name of 1 to \(DatabaseConfiguration.nameLimit) characters."
        }
        let others = configuration.services.filter { $0.id != editedID }
        if others.contains(where: { DatabaseConfiguration.trimmed($0.name) == trimmed }) {
            return "Each database service needs a unique name."
        }
        if portText.isEmpty { return nil }
        guard let port = PortInput.parse(portText) else { return PortInput.message }
        if let owner = others.first(where: { $0.port == port }) {
            return "Port \(port) is used by \(owner.name)."
        }
        return nil
    }

    /// The service to save, or nil while a rule fails or the port is still empty.
    public func service(in configuration: DatabaseConfiguration) -> DatabaseService? {
        guard issue(in: configuration) == nil, let runtimeID, let port = PortInput.parse(portText) else { return nil }
        let name = DatabaseConfiguration.trimmed(name)
        switch mode {
        case .add:
            return DatabaseService(name: name, runtimeID: runtimeID, port: port)
        case .edit(let saved):
            return DatabaseService(id: saved.id, name: name, runtimeID: saved.runtimeID, port: port)
        }
    }

    private var editedID: UUID? {
        if case .edit(let service) = mode { return service.id }
        return nil
    }
}
