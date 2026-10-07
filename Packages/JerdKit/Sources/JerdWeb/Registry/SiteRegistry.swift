import Foundation
import JerdFoundation

/// The loaded site configuration and its compare-and-swap save. It holds nothing else.
///
/// Memory changes only after a successful save, so a snapshot always equals the saved file.
public actor SiteRegistry {
    private let store: any ConfigurationStoring
    private var configuration: AppConfiguration?
    private var writing = false

    public init(store: any ConfigurationStoring) {
        self.store = store
    }

    /// Loads the saved configuration. Until a load succeeds, every other call fails.
    public func load() async throws -> AppConfiguration {
        guard !writing else { throw JerdError.invalid("A configuration operation is in progress.") }
        writing = true
        defer { writing = false }
        let loaded = try await store.load()
        configuration = loaded
        return loaded
    }

    /// The configuration that is saved now.
    public func snapshot() throws -> AppConfiguration {
        guard let configuration else {
            throw JerdError.corrupt("Load valid site settings before making changes.")
        }
        return configuration
    }

    /// Saves `next` only when the saved configuration still equals `previous`.
    public func replace(_ next: AppConfiguration, expecting previous: AppConfiguration) async throws -> AppConfiguration
    {
        guard let configuration else {
            throw JerdError.corrupt("Load a valid configuration before making changes.")
        }
        guard configuration == previous else {
            throw JerdError.unavailable("The site settings changed. Review the edit again.")
        }
        guard !writing else { throw JerdError.invalid("A configuration operation is in progress. Retry the change.") }
        writing = true
        defer { writing = false }
        try await store.save(next)
        self.configuration = next
        return next
    }
}
