import Foundation
import JerdDatabases

/// The fields of the Restore Database sheet: a new name and a free port for retained data. The
/// original runtime and data folder stay in use.
public struct RestoreDraft: Equatable, Sendable {
    public let database: RetainedDatabase
    public var name: String
    public var portText: String

    public init(database: RetainedDatabase) {
        self.database = database
        name = database.name
        portText = database.port.map(String.init) ?? ""
    }

    /// The first rule that the fields break, or nil.
    public func issue(in configuration: DatabaseConfiguration) -> String? {
        let trimmed = DatabaseConfiguration.trimmed(name)
        if trimmed.isEmpty { return "Enter a name." }
        guard DatabaseConfiguration.isValidName(name) else {
            return "Use a name of 1 to \(DatabaseConfiguration.nameLimit) characters."
        }
        if configuration.services.contains(where: { DatabaseConfiguration.trimmed($0.name) == trimmed }) {
            return "Each database service needs a unique name."
        }
        guard let port = PortInput.parse(portText) else { return PortInput.message }
        if let owner = configuration.services.first(where: { $0.port == port }) {
            return "Port \(port) is used by \(owner.name)."
        }
        return nil
    }

    /// The trimmed name and the port, or nil while a rule fails.
    public func values(in configuration: DatabaseConfiguration) -> (name: String, port: UInt16)? {
        guard issue(in: configuration) == nil, let port = PortInput.parse(portText) else { return nil }
        return (DatabaseConfiguration.trimmed(name), port)
    }
}
