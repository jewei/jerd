import Foundation
import JerdFoundation
import JerdProcess
import JerdSystem
import JerdWeb
import Testing

@testable import JerdLive

@Suite("Helper system setup port")
struct HelperSystemSetupTests {
    @Test func configureSendsTheValidatedRegistration() async throws {
        let helper = RecordingHelper()
        let setup = HelperSystemSetup(helper: helper)

        try await setup.configure(
            HTTPSRegistration(
                installationID: Fixture.installationID, hostnames: ["shop.test"],
                certificateDER: try Fixture.certificate(), trustPolicy: .serverTLS))

        #expect(
            await helper.calls == [
                .configure(hostnames: ["shop.test"], installationID: Fixture.installationID, policy: .serverTLS)
            ])
    }

    @Test func listenersBecomeInheritedDescriptorsInTheSameOrder() async throws {
        let helper = RecordingHelper()
        let listeners = try await HelperSystemSetup(helper: helper).acquireListeners()
        defer {
            try? listeners.http.close()
            try? listeners.https.close()
        }

        #expect(listeners.http.fileDescriptor != listeners.https.fileDescriptor)
        #expect(await helper.calls == [.acquireListeners])
    }

    @Test func statusReadsTheHelper() async throws {
        let helper = RecordingHelper(
            status: HelperStatus(availability: .enabled, setup: SystemSetupStatus(hostnames: ["a.test"])))

        let status = try await HelperSystemSetup(helper: helper).status()

        #expect(status.hostnames == ["a.test"])
    }

    @Test func releaseAndRemovePassThrough() async throws {
        let helper = RecordingHelper()
        let setup = HelperSystemSetup(helper: helper)

        await setup.releaseListeners()
        try await setup.removeSetup()

        #expect(await helper.calls == [.releaseListeners, .removeSetup])
    }
}
