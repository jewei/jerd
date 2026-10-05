import Foundation
import JerdFoundation

/// Composer: the verified `composer.phar` (mode 0600; PHP runs it) and its pinned license.
package struct ComposerPharPreparer: RuntimePreparing {
    package init() {}

    package func prepare(_ context: PreparationContext) async throws {
        let artifact = try context.requireArtifact()
        let phar = context.payload.appendingPathComponent("composer.phar")
        try await BlockingWork.run {
            try FileManager.default.copyItem(at: artifact, to: phar)
            guard chmod(phar.path, 0o600) == 0 else {
                throw JerdError.unavailable("Cannot protect \(phar.path) (\(SystemError.describe(errno))).")
            }
        }
        if let license = try PinnedLicense.of(.composer) {
            try await license.fetch(to: context.payload.appendingPathComponent("LICENSE"), using: context.fetcher)
        }
    }
}
