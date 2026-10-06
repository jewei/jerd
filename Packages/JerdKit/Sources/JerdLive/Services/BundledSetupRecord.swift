/// The result of the last bundled runtime setup of one service. The live ports are values, so
/// each port and its copies share one record, and the page can read the reason after the load.
package actor BundledSetupRecord {
    /// The user message of the last failed setup, or nil after a success or before any setup.
    package private(set) var failure: String?

    package init() {}

    /// Keeps the outcome of one setup: nil for a success, else the reason.
    package func record(_ failure: String?) {
        self.failure = failure
    }
}
