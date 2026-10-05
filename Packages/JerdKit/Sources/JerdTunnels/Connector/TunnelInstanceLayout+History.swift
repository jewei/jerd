import Foundation
import JerdFoundation

extension TunnelInstanceLayout {
    /// `server.previous.log`: the output of earlier connector runs. Only `ConnectorLogHistory` writes it.
    package var previousLogFile: URL {
        root.appendingPathComponent(ServiceFileName.previousLog, isDirectory: false)
    }
}
