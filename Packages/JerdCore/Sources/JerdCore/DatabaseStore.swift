import Foundation

public actor DatabaseStore {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("services.json") }
    public init(directory: URL) { self.directory = directory }

    public func load() throws -> DatabaseConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return DatabaseConfiguration() }
        do { return try decode(Data(contentsOf: fileURL)) }
        catch { throw JerdError.corruptConfiguration("Cannot read database settings. The file was preserved. \(error.localizedDescription)") }
    }

    public func save(_ configuration: DatabaseConfiguration) throws {
        try configuration.validate()
        try PrivateFiles.directory(directory)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let previous = try Data(contentsOf: fileURL)
            let old = try decode(previous)
            for service in configuration.services {
                if let existing = old.services.first(where: { $0.id == service.id }), existing.runtimeID != service.runtimeID {
                    throw JerdError.invalid("Create a separate service to use a different database version. Existing data cannot be reassigned.")
                }
            }
            for runtime in configuration.runtimes {
                if let existing = old.runtimes.first(where: { $0.id == runtime.id }), existing != runtime {
                    throw JerdError.invalid("An installed database runtime cannot be replaced under the same ID.")
                }
            }
            try PrivateFiles.write(previous, to: directory.appendingPathComponent("services.previous.json"))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try PrivateFiles.write(encoder.encode(configuration), to: fileURL)
    }

    private func decode(_ data: Data) throws -> DatabaseConfiguration {
        guard data.count <= 1_048_576 else { throw JerdError.corruptConfiguration("Database settings exceed the size limit.") }
        let configuration = try JSONDecoder().decode(DatabaseConfiguration.self, from: data)
        try configuration.validate()
        return configuration
    }
}
