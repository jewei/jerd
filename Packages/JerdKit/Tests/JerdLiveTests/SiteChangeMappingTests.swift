import Foundation
import JerdWeb
import Testing

@testable import JerdLive

@Suite("Site change mapping")
struct SiteChangeMappingTests {
    @Test func theApprovalListsTheApprovedHostnamesThatTheSetupLeavesOut() throws {
        let id = UUID()
        let setup = try SampleWeb.setup(hostnames: ["new.test", "shop.test"])

        let approval = SiteChangeMapping.approval(
            id: id, setup: setup, approvedHostnames: ["zoo.test", "shop.test", "old.test"])

        #expect(approval.id == id)
        #expect(approval.hostnames == ["new.test", "shop.test"])
        #expect(approval.removedHostnames == ["old.test", "zoo.test"])
        #expect(approval.fingerprint == setup.fingerprint)
    }

    @Test func aFirstApprovalRemovesNothing() throws {
        let approval = SiteChangeMapping.approval(
            id: UUID(), setup: try SampleWeb.setup(hostnames: ["shop.test"]), approvedHostnames: [])

        #expect(approval.removedHostnames.isEmpty)
    }
}
