import JerdRuntimes

/// Removes staging folders that a crash left behind. `BundledRuntimeBootstrap` and the runtime
/// installer of the Runtimes page are the live types.
package protocol StagingCleaning: Sendable {
    @discardableResult
    func removeAbandonedStaging() async -> [String]
}

extension BundledRuntimeBootstrap: StagingCleaning {}
