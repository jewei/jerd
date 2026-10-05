import Foundation
import JerdFoundation

/// Loads and saves the site configuration. The registry depends on this role so tests can use a fake.
public protocol ConfigurationStoring: Sendable {
    /// The saved configuration. An absent file is an empty configuration.
    /// - Throws: `.corrupt` when the file cannot be read; the file is preserved.
    func load() async throws -> AppConfiguration
    /// Saves after the old valid bytes are copied to the backup file.
    func save(_ configuration: AppConfiguration) async throws
}

/// The live store of `configuration.json`. It is the only writer of the file.
public actor ConfigurationStore: ConfigurationStoring {
    private let store: JSONDocumentStore<AppConfiguration>

    public init(layout: DataLayout) {
        store = ConfigurationCodec.store(in: layout)
    }

    public func load() throws -> AppConfiguration {
        try store.load() ?? AppConfiguration()
    }

    public func save(_ configuration: AppConfiguration) throws {
        try store.save(configuration)
    }
}
