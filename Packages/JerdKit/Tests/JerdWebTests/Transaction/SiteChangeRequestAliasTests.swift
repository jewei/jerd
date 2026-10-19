import Foundation
import Testing

@testable import JerdWeb

@Suite struct SiteChangeRequestAliasTests {
    @Test func aRemovedAliasLeavesTheApprovalAndAKeptAliasStays() {
        var site = Samples.site(URL(fileURLWithPath: "/p/app"), hostname: "app.test")
        site.aliases = ["a.app.test", "b.app.test"]
        var edited = site
        edited.aliases = ["b.app.test"]
        let request = SiteChangeRequest(
            previous: Samples.configuration([site]), candidate: Samples.configuration([edited]),
            selection: .keepRunning(startIfStopped: false))
        #expect(request.removedHostnames == ["a.app.test"])
        #expect(request.registeredHostnames == ["app.test", "b.app.test"])
    }
}
