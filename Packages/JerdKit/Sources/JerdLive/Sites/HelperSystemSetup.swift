import JerdProcess
import JerdSystem
import JerdWeb

/// The web layer's `SystemSetupPort`, implemented with the JerdSystem helper client.
package struct HelperSystemSetup: SystemSetupPort {
    let helper: any HelperControlling

    package init(helper: any HelperControlling) {
        self.helper = helper
    }

    package func status() async throws -> HTTPSSetupStatus {
        try HelperStatusMapping.httpsStatus(try await helper.status())
    }

    package func configure(_ registration: HTTPSRegistration) async throws {
        let request = try HelperStatusMapping.request(for: registration)
        try await helper.configure(
            hostnames: request.hostnames, caCertificate: request.certificate, policy: request.policy)
    }

    /// The helper's sockets for ports 80 and 443, as inherited descriptors for Caddy.
    package func acquireListeners() async throws -> InheritedListeners {
        let pair = try await helper.acquireListeners()
        return InheritedListeners(http: pair.http, https: pair.https)
    }

    package func releaseListeners() async {
        await helper.releaseListeners()
    }

    package func removeSetup() async throws {
        try await helper.removeSetup()
    }
}
