import JerdFoundation
import JerdWeb

@testable import JerdLive

/// A registry in memory. `load()` fails while `loadFailures` is above zero.
actor FakeSiteRegistry: SiteConfigurationLoading {
    private(set) var configuration: AppConfiguration
    private(set) var loadCount = 0
    private var loadFailures: Int

    init(_ configuration: AppConfiguration = AppConfiguration(), loadFailures: Int = 0) {
        self.configuration = configuration
        self.loadFailures = loadFailures
    }

    func load() async throws -> AppConfiguration {
        loadCount += 1
        // Lets a concurrent caller arrive while the first load runs.
        await Task.yield()
        if loadFailures > 0 {
            loadFailures -= 1
            throw JerdError.corrupt("The site configuration is corrupt.")
        }
        return configuration
    }

    func snapshot() throws -> AppConfiguration { configuration }

    /// The records part of `SiteChangeReducer`, enough for the runtime changes.
    func reduce(_ change: SiteChange) {
        switch change {
        case .upsertRuntime(let runtime):
            configuration.runtimes.append(runtime)
            if configuration.defaultRuntimeID == nil { configuration.defaultRuntimeID = runtime.id }
        case .caddy(let caddy):
            configuration.caddy = caddy
        default:
            break
        }
    }
}
