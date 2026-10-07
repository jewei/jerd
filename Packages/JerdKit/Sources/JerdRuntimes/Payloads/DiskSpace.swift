import Darwin
import Foundation
import JerdFoundation

/// Recognizes a failure because the volume is full, wherever an installation step hit it, so the
/// user gets one message with the step that fixes it.
package enum DiskSpace {
    /// The message of every installation that the disk space stopped.
    package static let outOfSpace = JerdError.unavailable(
        "There is not enough free disk space to install this runtime. Free some space, then try again.")

    /// True when `error` says that the volume or the user quota is full.
    package static func isOutOfSpace(_ error: any Error) -> Bool {
        if let jerd = error as? JerdError {
            return [ENOSPC, EDQUOT].contains { jerd.message.contains(SystemError.describe($0)) }
        }
        if let error = error as? POSIXError { return [.ENOSPC, .EDQUOT].contains(error.code) }
        if let error = error as? CocoaError { return error.code == .fileWriteOutOfSpace }
        let error = error as NSError
        if error.domain == NSPOSIXErrorDomain { return [ENOSPC, EDQUOT].contains(Int32(error.code)) }
        return error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileWriteOutOfSpace.rawValue
    }
}
