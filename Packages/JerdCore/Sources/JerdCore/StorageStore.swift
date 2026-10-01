import Foundation

public actor StorageStore {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("settings.json") }
    public init(directory: URL) { self.directory = directory }

    public func load() throws -> StorageConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return StorageConfiguration() }
        do { return try decode(Data(contentsOf: fileURL)) }
        catch { throw JerdError.corruptConfiguration("Cannot read storage settings. The file was preserved. \(error.localizedDescription)") }
    }

    public func save(_ configuration: StorageConfiguration) throws {
        try configuration.validate()
        try PrivateFiles.directory(directory)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let previous = try Data(contentsOf: fileURL)
            let old = try decode(previous)
            if let runtime = old.runtime, runtime != configuration.runtime {
                throw JerdError.invalid("The saved RustFS runtime cannot be replaced. Stored objects were preserved.")
            }
            try PrivateFiles.write(previous, to: directory.appendingPathComponent("settings.previous.json"))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try PrivateFiles.write(encoder.encode(configuration), to: fileURL)
    }

    private func decode(_ data: Data) throws -> StorageConfiguration {
        guard data.count <= 1_048_576 else { throw JerdError.corruptConfiguration("Storage settings exceed the size limit.") }
        let configuration = try JSONDecoder().decode(StorageConfiguration.self, from: data)
        try configuration.validate()
        return configuration
    }
}
