import Foundation
import JerdFoundation

/// The one reader and writer of `tunnels/settings.json` and its backup `settings.previous.json`.
///
/// It keeps the exact encoding (pretty, sorted keys, unescaped slashes) and never overwrites a
/// file that it cannot read. `TunnelSupervisor` is the only writer; the web route source reads
/// through this same codec on its own actor. Atomic replacement keeps those reads complete.
package struct TunnelStore: Sendable {
    /// The largest settings file that Jerd reads (256 KiB).
    package static let sizeLimit = 262_144

    private let document: JSONDocumentStore<TunnelConfiguration>

    package init(layout: TunnelsLayout) {
        document = JSONDocumentStore(
            file: layout.settingsFile, previousFile: layout.previousSettingsFile, sizeLimit: Self.sizeLimit,
            format: .settings, name: TunnelMessage.settingsName,
            decode: { data, decoder in
                let version = try SchemaVersion.read(from: data, decoder: decoder)
                guard version == TunnelConfiguration.currentSchemaVersion else {
                    throw SchemaVersion.unsupported(version)
                }
                return try decoder.decode(TunnelConfiguration.self, from: data)
            },
            validate: { try $0.validate() })
    }

    /// The saved settings, or empty settings when the file is absent. Never writes.
    /// - Throws: `.corrupt` ("Cannot read tunnel settings. The file was preserved. …").
    package func load() throws -> TunnelConfiguration {
        try document.load() ?? TunnelConfiguration()
    }

    /// Validates and saves `configuration`, after it copies the old file to the backup.
    package func save(_ configuration: TunnelConfiguration) throws {
        try document.save(configuration)
    }
}
