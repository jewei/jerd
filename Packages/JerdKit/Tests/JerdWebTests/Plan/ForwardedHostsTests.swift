import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct ForwardedHostsTests {
    private let site = UUID()
    private let first = PublicHostname("a.example.com")!
    private let second = PublicHostname("b.example.com")!

    @Test func theHostsOfASiteAreSorted() {
        #expect(ForwardedHosts([site: [second, first]]).hosts(of: site) == [first, second])
        #expect(ForwardedHosts([site: [first]]).hosts(of: UUID()).isEmpty)
    }

    /// Equal mappings compare equal, so an unchanged mapping never restarts the run.
    @Test func aSiteWithoutHostsIsTheSameAsNoEntry() {
        #expect(ForwardedHosts([site: []]) == .none)
        #expect(ForwardedHosts([site: [first], UUID(): []]) == ForwardedHosts([site: [first]]))
    }

    @Test func limitingKeepsOnlyTheNamedSites() {
        let other = UUID()
        let hosts = ForwardedHosts([site: [first], other: [second]])
        #expect(hosts.limited(to: [site]) == ForwardedHosts([site: [first]]))
        #expect(hosts.limited(to: []) == .none)
    }
}
