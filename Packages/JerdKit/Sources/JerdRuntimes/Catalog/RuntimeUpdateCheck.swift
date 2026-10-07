import Foundation
import JerdManifest

/// The result of one catalog check. Errors are data: the page shows them beside the runtime.
public struct RuntimeUpdateCheck: Sendable {
    public let kind: RuntimeKind
    /// Installable releases, newest first. Empty when `error` is set.
    public let releases: [RuntimeRelease]
    public let checkedAt: Date
    /// The user message of the failure.
    public let error: String?

    public init(kind: RuntimeKind, releases: [RuntimeRelease], checkedAt: Date, error: String?) {
        self.kind = kind
        self.releases = releases
        self.checkedAt = checkedAt
        self.error = error
    }
}
