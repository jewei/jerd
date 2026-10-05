import Foundation
import JerdFoundation

/// The settings file of one service (`services.json` or `settings.json`), on top of
/// `JSONDocumentStore`: settings encoding, a previous copy, a size limit, and a schema version.
///
/// A corrupt or unsupported file is never replaced: load and save throw `.corrupt` and keep its bytes.
public struct ServiceSettingsStore<Settings: Codable & Sendable>: Sendable {
    public let document: JSONDocumentStore<Settings>

    /// - Parameters:
    ///   - name: the name in messages, for example "database settings".
    ///   - schemaVersion: the only `schemaVersion` this build reads. The key is required.
    ///   - validate: structural rules for every load and save.
    ///   - admit: rules that compare a save with the saved settings.
    public init(
        file: URL, previousFile: URL, sizeLimit: Int, name: String, schemaVersion: Int = 1,
        validate: @escaping JSONDocumentStore<Settings>.Validate = { _ in },
        admit: @escaping JSONDocumentStore<Settings>.Admit = { _, _ in }
    ) {
        document = JSONDocumentStore(
            file: file, previousFile: previousFile, sizeLimit: sizeLimit, format: .settings, name: name,
            decode: { data, decoder in
                let version = try SchemaVersion.read(from: data, decoder: decoder)
                guard version == schemaVersion else { throw SchemaVersion.unsupported(version) }
                return try decoder.decode(Settings.self, from: data)
            },
            validate: validate, admit: admit)
    }

    private init(document: JSONDocumentStore<Settings>) { self.document = document }

    /// The saved settings, or `defaults` when the file is absent. Nothing is written.
    public func load(orDefault defaults: Settings) throws -> Settings {
        try document.load() ?? defaults
    }

    /// Validates and saves `settings`, after a copy of the saved bytes to the previous file.
    public func save(_ settings: Settings) throws {
        try document.save(settings)
    }

    /// A copy whose saves must also pass `extra`, for a rule of one operation.
    public func admitting(_ extra: @escaping JSONDocumentStore<Settings>.Admit) -> ServiceSettingsStore {
        ServiceSettingsStore(document: document.admitting(extra))
    }
}
