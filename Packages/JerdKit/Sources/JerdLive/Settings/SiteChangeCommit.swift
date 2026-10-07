import JerdFoundation
import JerdWeb

/// The result rule of runtime record changes from Settings. These pages have no approval
/// sheet, so a change that waits for HTTPS approval is reported instead of kept.
package enum SiteChangeCommit {
    package static let approvalMessage =
        "This change needs HTTPS approval. Start the sites in Sites to review the approval, then retry."

    /// The saved configuration of a committed change.
    /// - Throws: `.unavailable` when the change waits for approval. Nothing was saved for it.
    package static func require(_ result: SiteChangeStep) throws -> AppConfiguration {
        guard case .committed(let configuration) = result else {
            throw JerdError.unavailable(approvalMessage)
        }
        return configuration
    }
}
