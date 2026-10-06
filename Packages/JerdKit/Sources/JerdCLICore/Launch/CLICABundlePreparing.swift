import Foundation
import JerdFoundation
import JerdWeb

/// Prepares the CLI CA bundle `runtimes/configuration/php-ca.pem`. Tests inject the answer.
public protocol CLICABundlePreparing: Sendable {
    /// The bundle, or nil when the local CA does not exist or macOS does not trust it.
    func prepareForCLI(layout: DataLayout) throws -> URL?
}

/// JerdWeb's builder is the live preparer, so FPM and the CLI share one bundle rule.
extension PHPCABundleBuilder: CLICABundlePreparing {}
