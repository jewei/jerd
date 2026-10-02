import Foundation
import Darwin

public enum PrivateFiles {
    public static func directory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let info = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard info.isSymbolicLink != true, info.isDirectory == true else {
            throw JerdError.invalid("Expected an app-owned directory: \(url.path)")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    // The temporary file is on the same volume. fsync precedes the atomic rename.
    public static func write(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw JerdError.invalid("Cannot create private file: \(temporary.path)") }
        defer { close(fd); try? FileManager.default.removeItem(at: temporary) }
        try data.withUnsafeBytes { buffer in
            var written = 0
            while written < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: written), buffer.count - written)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw JerdError.invalid("Cannot write \(url.path)") }
                written += count
            }
        }
        guard fsync(fd) == 0, rename(temporary.path, url.path) == 0 else {
            throw JerdError.invalid("Cannot save \(url.path)")
        }
        let parent = open(url.deletingLastPathComponent().path, O_RDONLY)
        if parent >= 0 { _ = fsync(parent); close(parent) }
    }
}

public protocol ConfigurationStore: Sendable {
    func load() async throws -> AppConfiguration
    func save(_ configuration: AppConfiguration) async throws
}

public actor JSONConfigurationStore: ConfigurationStore {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("configuration.json") }
    public init(directory: URL) { self.directory = directory }

    public static var applicationDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Jerd", isDirectory: true)
    }

    public func load() throws -> AppConfiguration {
        try Self.loadConfiguration(from: directory)
    }

    public static func loadConfiguration(from directory: URL) throws -> AppConfiguration {
        let fileURL = directory.appendingPathComponent("configuration.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return AppConfiguration() }
        do { return try decode(Data(contentsOf: fileURL)) }
        catch {
            throw JerdError.corruptConfiguration("Cannot read \(fileURL.path). The file was preserved. \(error.localizedDescription)")
        }
    }

    public func save(_ configuration: AppConfiguration) throws {
        try Self.validateStructure(configuration)
        try PrivateFiles.directory(directory)
        // Never overwrite a corrupt or unsupported document, even after a failed load.
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let previous = try Data(contentsOf: fileURL)
            _ = try Self.decode(previous)
            try PrivateFiles.write(previous, to: directory.appendingPathComponent("configuration.previous.json"))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try PrivateFiles.write(encoder.encode(configuration), to: fileURL)
    }

    private static func decode(_ data: Data) throws -> AppConfiguration {
        struct Header: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        let configuration: AppConfiguration
        switch header.schemaVersion {
        case 0:
            // The initial site-only development schema. Migration is saved on the next edit.
            struct V0: Decodable { let sites: [Site] }
            let old = try decoder.decode(V0.self, from: data)
            var upgraded = AppConfiguration()
            upgraded.sites = old.sites
            configuration = upgraded
        case AppConfiguration.currentVersion:
            configuration = try decoder.decode(AppConfiguration.self, from: data)
        default:
            throw JerdError.corruptConfiguration("Unsupported configuration version: \(header.schemaVersion).")
        }
        try validateStructure(configuration)
        return configuration
    }

    private static func validateStructure(_ configuration: AppConfiguration) throws {
        guard configuration.schemaVersion == AppConfiguration.currentVersion,
              Set(configuration.sites.map(\.id)).count == configuration.sites.count,
              Set(configuration.sites.map { $0.hostname.lowercased() }).count == configuration.sites.count,
              Set(configuration.sites.map(\.projectPath)).count == configuration.sites.count,
              Set(configuration.runtimes.map(\.id)).count == configuration.runtimes.count else {
            throw JerdError.corruptConfiguration("Configuration contains an invalid version or duplicate records.")
        }
        for site in configuration.sites {
            _ = try Hostname.validate(site.hostname)
            guard site.projectPath.hasPrefix("/"), site.documentRoot.hasPrefix("/"),
                  URL(fileURLWithPath: site.documentRoot).standardizedFileURL.pathComponents.starts(
                    with: URL(fileURLWithPath: site.projectPath).standardizedFileURL.pathComponents) else {
                throw JerdError.corruptConfiguration("Configuration contains an invalid project path.")
            }
        }
    }
}
