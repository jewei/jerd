import Foundation
import JerdWeb

/// The environment coordinator calls that the Sites port uses. `EnvironmentCoordinator` is the
/// live type.
package protocol EnvironmentControlling: Sendable {
    func snapshot() async -> EnvironmentSnapshot
    func preparePublicHosts(for siteID: UUID) async throws
    /// The user's Stop, then a wait for the current operation, then the stop of the run.
    func stop() async
}

extension EnvironmentCoordinator: EnvironmentControlling {}
