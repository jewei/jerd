import Foundation
import JerdFoundation

/// Removal of private files that hold a secret. A failure is always reported, because the file
/// keeps the secret on disk.
enum SecretFiles {
    /// Removes each file without following a link. A missing file is not an error.
    /// - Throws: `.unavailable` that names each file that is still there.
    static func remove(_ files: [URL]) throws {
        var kept: [String] = []
        for file in files {
            do {
                try AtomicFile.remove(file)
            } catch {
                kept.append(FailureDetail.describe(error))
            }
        }
        guard kept.isEmpty else { throw JerdError.unavailable(ServiceMessages.secretFilesKept(kept)) }
    }

    /// The error of a failed step with the removal failure added. It keeps the kind of the step
    /// error, and a retained process stays retained.
    static func combine(_ removal: any Error, after failure: any Error) -> any Error {
        let message = "\(FailureDetail.describe(failure)) \(FailureDetail.describe(removal))"
        if failure is RetainedProcessError { return RetainedProcessError(message: message) }
        return JerdError((failure as? JerdError)?.kind ?? .processFailed, message)
    }
}
