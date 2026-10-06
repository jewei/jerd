import Foundation

extension LaunchPlan {
    /// Removes every secret file. A missing file is not an error.
    /// - Throws: `.unavailable` that names each file that is still there.
    public func removeSecretFiles() throws {
        try SecretFiles.remove(secretFiles)
    }

    /// Cleans up a plan that never launches, for example after a failed configuration write:
    /// removes the temporary items and the secret files.
    /// - Returns: `failure`, or a combined error when a secret file is still there.
    public func discard(after failure: any Error) -> any Error {
        removeTemporaryItems()
        do {
            try removeSecretFiles()
            return failure
        } catch {
            return SecretFiles.combine(error, after: failure)
        }
    }
}
