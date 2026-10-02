import Foundation

public actor MailStore {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("settings.json") }
    public init(directory: URL) { self.directory = directory }

    public func load() throws -> MailConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return MailConfiguration() }
        do { return try decode(Data(contentsOf: fileURL)) }
        catch { throw JerdError.corruptConfiguration("Cannot read mail settings. The file was preserved. \(error.localizedDescription)") }
    }

    public func save(_ configuration: MailConfiguration) throws {
        try save(configuration, replacingRuntime: nil)
    }

    func save(_ configuration: MailConfiguration, replacingRuntime expected: MailRuntime?) throws {
        try configuration.validate()
        try PrivateFiles.directory(directory)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let previous = try Data(contentsOf: fileURL)
            let old = try decode(previous)
            if let runtime = old.runtime, runtime != configuration.runtime, runtime != expected {
                throw JerdError.invalid("The saved Mailpit runtime cannot be replaced. The inbox was preserved.")
            }
            try PrivateFiles.write(previous, to: directory.appendingPathComponent("settings.previous.json"))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try PrivateFiles.write(encoder.encode(configuration), to: fileURL)
    }

    private func decode(_ data: Data) throws -> MailConfiguration {
        guard data.count <= 65_536 else { throw JerdError.corruptConfiguration("Mail settings exceed the size limit.") }
        let configuration = try JSONDecoder().decode(MailConfiguration.self, from: data)
        try configuration.validate()
        return configuration
    }
}
