import JerdSystem
import JerdUI

/// The `HTTPSRecoveryPort` of Advanced, implemented with the helper client.
package struct LiveHTTPSRecovery: HTTPSRecoveryPort {
    let helper: any HelperControlling

    package init(helper: any HelperControlling) {
        self.helper = helper
    }

    /// The interrupted transaction, or nil. A disabled helper reports an empty setup, so nil.
    /// A transaction that runs now throws, because it is not interrupted.
    package func pendingRecovery() async throws -> SystemRecoveryStatus? {
        try HelperStatusMapping.pendingRecovery(try await helper.status())
    }

    package func recover(_ status: SystemRecoveryStatus, action: SystemRecoveryAction) async throws {
        try await helper.recover(report: status, action: action)
    }
}
