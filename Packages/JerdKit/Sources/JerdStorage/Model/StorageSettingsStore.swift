import JerdFoundation
import JerdServiceKit

/// The only reader and writer of `storage/settings.json`.
///
/// Rules:
/// - A missing file loads as the default settings and is not written.
/// - A corrupt or unsupported file is never replaced; its bytes stay for inspection.
/// - A save copies the saved bytes to `settings.previous.json` first.
/// - The saved runtime never changes, except in a runtime update that names it.
struct StorageSettingsStore: Sendable {
    /// The largest `settings.json`.
    static let sizeLimit = 1_048_576

    private let store: ServiceSettingsStore<StorageSettings>

    init(layout: StorageLayout) {
        store = ServiceSettingsStore(
            file: layout.settingsFile, previousFile: layout.previousSettingsFile, sizeLimit: Self.sizeLimit,
            name: "storage settings", schemaVersion: StorageSettings.supportedVersion,
            validate: { try $0.validate() })
    }

    func load() throws -> StorageSettings {
        try store.load(orDefault: StorageSettings())
    }

    /// Saves `settings`. The saved runtime may change only to replace `replacing`.
    func save(_ settings: StorageSettings, replacing: StorageRuntime? = nil) throws {
        try store.admitting { saved, new in
            guard let old = saved?.runtime, old != new.runtime, old != replacing else { return }
            throw StorageMessages.runtimeNotReplaceable
        }
        .save(settings)
    }
}
