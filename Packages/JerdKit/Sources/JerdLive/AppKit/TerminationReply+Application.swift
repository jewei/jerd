import AppKit
import JerdUI

extension TerminationReply {
    /// The reply of `applicationShouldTerminate`. `later` promises exactly one
    /// `reply(toApplicationShouldTerminate:)`, which the staged quit sends.
    public var applicationReply: NSApplication.TerminateReply {
        switch self {
        case .now: .terminateNow
        case .later: .terminateLater
        case .cancel: .terminateCancel
        }
    }
}
