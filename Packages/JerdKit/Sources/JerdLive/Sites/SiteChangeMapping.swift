import Foundation
import JerdUI
import JerdWeb

/// Pure mappings from the web layer's change results to the values of the Sites page.
package enum SiteChangeMapping {
    /// The approval sheet of a waiting change.
    /// - Parameters:
    ///   - id: The key under which the port keeps the waiting change.
    ///   - approvedHostnames: The hostnames of the setup that the helper reports now. Those that
    ///     the new setup leaves out are the ones the change removes.
    package static func approval(id: UUID, setup: HTTPSSetup, approvedHostnames: [String]) -> HTTPSApproval {
        let kept = Set(setup.hostnames)
        return HTTPSApproval(
            id: id, hostnames: setup.hostnames,
            removedHostnames: approvedHostnames.filter { !kept.contains($0) }.sorted(),
            fingerprint: setup.fingerprint)
    }
}
