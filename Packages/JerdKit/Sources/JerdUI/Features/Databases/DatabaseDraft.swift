import Foundation
import JerdDatabases

/// The fields of the Add and Edit Database sheet and their rules. The engine and the version
/// are fixed after Add, because the data folder uses them.
public struct DatabaseDraft: Equatable, Sendable {
    /// What the sheet saves.
    public enum Mode: Equatable, Sendable {
        case add
        case edit(DatabaseService)
    }

    public let mode: Mode
    public private(set) var engine: DatabaseEngine
    public var runtimeID: String?
    public private(set) var name: String
    public private(set) var portText: String
    /// True after the user typed a name, so an engine change keeps it.
    public private(set) var hasCustomName = false
    /// True after the user typed a port, so a late suggestion never replaces it.
    public private(set) var hasCustomPort = false

    /// A new service of `engine` with its first runtime and a free name. The port follows
    /// from `applySuggestedPort`.
    public static func add(_ engine: DatabaseEngine, in configuration: DatabaseConfiguration) -> DatabaseDraft {
        DatabaseDraft(
            mode: .add, engine: engine, runtimeID: configuration.runtimes.first { $0.engine == engine }?.id,
            name: defaultName(for: engine, in: configuration), portText: "")
    }

    /// The saved values of `service`.
    public static func edit(_ service: DatabaseService, engine: DatabaseEngine) -> DatabaseDraft {
        DatabaseDraft(
            mode: .edit(service), engine: engine, runtimeID: service.runtimeID, name: service.name,
            portText: String(service.port))
    }

    public var isAdding: Bool { mode == .add }

    public mutating func setName(_ name: String) {
        guard name != self.name else { return }
        self.name = name
        hasCustomName = true
    }

    public mutating func setPort(_ text: String) {
        guard text != portText else { return }
        portText = text
        hasCustomPort = true
    }

    /// Selects another engine while adding: its first runtime, its default name unless the user
    /// typed one, and an empty port until the new suggestion arrives.
    public mutating func changeEngine(_ engine: DatabaseEngine, in configuration: DatabaseConfiguration) {
        guard isAdding, engine != self.engine else { return }
        self.engine = engine
        runtimeID = configuration.runtimes.first { $0.engine == engine }?.id
        if !hasCustomName { name = Self.defaultName(for: engine, in: configuration) }
        if !hasCustomPort { portText = "" }
    }

    /// Fills the port with a suggestion for `engine`, unless the user typed one or the engine
    /// changed while the suggestion ran.
    public mutating func applySuggestedPort(_ port: UInt16, for engine: DatabaseEngine) {
        guard engine == self.engine, !hasCustomPort else { return }
        portText = String(port)
    }

    /// The engine title, or the first free "Title 2", "Title 3", … name.
    static func defaultName(for engine: DatabaseEngine, in configuration: DatabaseConfiguration) -> String {
        let names = Set(configuration.services.map { DatabaseConfiguration.trimmed($0.name) })
        guard names.contains(engine.title) else { return engine.title }
        var number = 2
        while names.contains("\(engine.title) \(number)") { number += 1 }
        return "\(engine.title) \(number)"
    }
}
