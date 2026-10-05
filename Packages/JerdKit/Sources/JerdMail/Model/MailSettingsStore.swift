import JerdFoundation
import JerdServiceKit

/// The only reader and writer of `mail/settings.json`.
///
/// Rules:
/// - A missing file loads as the default settings and is not written.
/// - A corrupt or unsupported file is never replaced; its bytes stay for inspection.
/// - A save copies the saved bytes to `settings.previous.json` first.
/// - The saved runtime never changes, except in a runtime update that names it.
struct MailSettingsStore: Sendable {
    /// The largest `settings.json`.
    static let sizeLimit = 65_536

    private let store: ServiceSettingsStore<MailSettings>

    init(layout: MailLayout) {
        store = ServiceSettingsStore(
            file: layout.settingsFile, previousFile: layout.previousSettingsFile, sizeLimit: Self.sizeLimit,
            name: "mail settings", schemaVersion: MailSettings.supportedVersion, validate: { try $0.validate() })
    }

    func load() throws -> MailSettings {
        try store.load(orDefault: MailSettings())
    }

    /// Saves `settings`. The saved runtime may change only to replace `replacing`.
    func save(_ settings: MailSettings, replacing: MailRuntime? = nil) throws {
        try store.admitting { saved, new in
            try Self.requireStableRuntime(saved: saved?.runtime, new: new.runtime, replacing: replacing)
        }
        .save(settings)
    }

    /// A saved runtime stays unless the save replaces exactly that runtime.
    static func requireStableRuntime(saved: MailRuntime?, new: MailRuntime?, replacing: MailRuntime?) throws {
        guard let saved, saved != new, saved != replacing else { return }
        throw MailMessages.runtimeNotReplaceable
    }
}
