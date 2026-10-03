import Foundation

public actor TunnelStore {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("settings.json") }
    public init(directory: URL) { self.directory = directory }
    public func load() throws -> TunnelConfiguration {
        guard PrivateFiles.exists(fileURL) else { return TunnelConfiguration() }
        do { return try decode(PrivateFiles.read(fileURL, limit: 262_144)) }
        catch { throw JerdError.corruptConfiguration("Cannot read tunnel settings. The file was preserved. \(error.localizedDescription)") }
    }
    public func save(_ configuration: TunnelConfiguration) throws {
        try configuration.validate()
        try PrivateFiles.directory(directory)
        if PrivateFiles.exists(fileURL) {
            let old = try PrivateFiles.read(fileURL, limit: 262_144)
            _ = try decode(old)
            try PrivateFiles.write(old, to: directory.appendingPathComponent("settings.previous.json"))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try PrivateFiles.write(encoder.encode(configuration), to: fileURL)
    }
    private func decode(_ data: Data) throws -> TunnelConfiguration {
        let value = try JSONDecoder().decode(TunnelConfiguration.self, from: data)
        try value.validate(); return value
    }
}
