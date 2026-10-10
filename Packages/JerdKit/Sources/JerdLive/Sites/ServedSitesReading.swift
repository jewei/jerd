import Foundation
import JerdWeb

/// What the web run served when the last site change ended. `SiteChangeTransaction` is the live
/// type. The route guard reads it, not the run, which serves no site during a restart.
package protocol ServedSitesReading: Sendable {
    /// The `.test` hostname of each served site, by site ID.
    var servedHostnames: [UUID: String] { get async }
}

extension SiteChangeTransaction: ServedSitesReading {}
