import Foundation
import JerdFoundation

@testable import JerdWeb

/// Mutable tunnel routes, including a read failure, without user settings files.
actor FakePublicHosts: SitePublicHostsLoading {
    private var hosts: Set<SitePublicHost> = []
    private var fails = false

    func set(_ hosts: Set<SitePublicHost>) { self.hosts = hosts }
    func rejectReads() { fails = true }

    func loadPublicHosts() throws -> Set<SitePublicHost> {
        if fails { throw JerdError.corrupt("Cannot read tunnel settings.") }
        return hosts
    }
}
