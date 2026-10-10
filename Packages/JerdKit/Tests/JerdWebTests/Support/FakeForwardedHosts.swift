import Foundation
import JerdFoundation

@testable import JerdWeb

/// Saved forwarded hosts that a test changes, or a read that fails, without user settings files.
actor FakeForwardedHosts: ForwardedHostsLoading {
    /// The error of a read that fails.
    static let readFailure = JerdError.corrupt("Cannot read tunnel settings. The file was preserved.")
    private var hosts = ForwardedHosts.none
    private var fails = false
    private(set) var reads = 0

    /// Saves `hostnames` for `siteID` and replaces all earlier hosts.
    func set(_ siteID: UUID, _ hostnames: [String]) {
        hosts = ForwardedHosts([siteID: Set(hostnames.compactMap(PublicHostname.init))])
    }

    func failReads() { fails = true }

    func loadForwardedHosts() throws -> ForwardedHosts {
        reads += 1
        if fails { throw Self.readFailure }
        return hosts
    }
}
