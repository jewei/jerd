import Foundation
import JerdFoundation

/// The exact JSON form of `configuration.json`: versioned decoding, the structure rules, and the encoder.
///
/// Rules:
/// - Version 0 (sites only) is migrated to version 1 in memory. The next save writes version 1.
/// - Version 1 is decoded in full. Any other version is corrupt and the file is preserved.
/// - Every loaded and saved configuration passes `validate(_:)`.
/// - The encoder is `JSONFileFormat.settings`: pretty, sorted keys, unescaped slashes, and the
///   default `Date` coding (seconds since 2001).
public enum ConfigurationCodec {
    /// The largest file that Jerd reads or writes.
    public static let sizeLimit = 8 * 1_048_576
    /// The short name in messages.
    public static let documentName = "the site configuration"

    /// Decodes either schema version.
    public static func decode(_ data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> AppConfiguration {
        switch try SchemaVersion.read(from: data, decoder: decoder) {
        case 0:
            return AppConfiguration(sites: try decoder.decode(VersionZero.self, from: data).sites)
        case AppConfiguration.currentVersion:
            return try decoder.decode(AppConfiguration.self, from: data)
        case let version:
            throw JerdError.corrupt("Unsupported configuration version: \(version).")
        }
    }

    /// The exact bytes that a save writes.
    public static func encode(_ configuration: AppConfiguration) throws -> Data {
        try JSONFileFormat.settings.makeEncoder().encode(configuration)
    }

    /// The structure rules: the current version, unique IDs, hostnames, and project paths, valid
    /// hostnames, absolute paths, and a document root inside its project.
    public static func validate(_ configuration: AppConfiguration) throws {
        let sites = configuration.sites
        guard configuration.schemaVersion == AppConfiguration.currentVersion,
            Set(sites.map(\.id)).count == sites.count,
            Set(sites.map { $0.hostname.lowercased() }).count == sites.count,
            Set(sites.map(\.projectPath)).count == sites.count,
            Set(configuration.runtimes.map(\.id)).count == configuration.runtimes.count
        else { throw JerdError.corrupt("Configuration contains an invalid version or duplicate records.") }
        for site in sites {
            _ = try HostnamePolicy.validate(site.hostname)
            guard site.projectPath.hasPrefix("/"), site.documentRoot.hasPrefix("/"),
                PathComponents.contains(site.documentRoot, in: site.projectPath)
            else { throw JerdError.corrupt("Configuration contains an invalid project path.") }
        }
    }

    /// The store of `configuration.json` and its backup `configuration.previous.json`.
    public static func store(in layout: DataLayout) -> JSONDocumentStore<AppConfiguration> {
        JSONDocumentStore(
            file: layout.configurationFile, previousFile: layout.previousConfigurationFile, sizeLimit: sizeLimit,
            format: .settings, name: documentName, decode: { data, decoder in try decode(data, decoder: decoder) },
            validate: validate)
    }

    /// The initial development schema: `{"schemaVersion":0,"sites":[…]}` with full site objects.
    private struct VersionZero: Decodable {
        let sites: [Site]
    }
}
