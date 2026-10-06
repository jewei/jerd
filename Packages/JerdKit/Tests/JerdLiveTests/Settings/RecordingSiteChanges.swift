import Foundation
import JerdFoundation
import JerdWeb

@testable import JerdLive

/// A site change transaction that applies each change with the real reducer to an in-memory
/// configuration and records it. It never runs or stops a site.
actor RecordingSiteChanges: SiteChangeApplying {
    private(set) var changes: [SiteChange] = []
    private(set) var configuration: AppConfiguration
    private let reducer = SiteChangeReducer(hosts: EmptyHosts())

    init(_ configuration: AppConfiguration = AppConfiguration()) {
        self.configuration = configuration
    }

    func apply(_ change: SiteChange, startIfStopped: Bool) throws -> SiteChangeStep {
        changes.append(change)
        configuration = try reducer.reduce(configuration, change)
        return .committed(configuration)
    }

    func run(_ siteIDs: Set<UUID>) throws -> SiteChangeStep { .committed(configuration) }

    func requestStop() {}
}

/// An empty hosts file, so the reducer reads nothing from `/etc/hosts`.
struct EmptyHosts: HostsFileReading {
    func read() throws -> String { "" }
}
