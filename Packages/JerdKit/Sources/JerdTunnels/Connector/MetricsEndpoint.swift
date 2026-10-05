import Foundation
import JerdProcess

/// The commands and pure rules of the connector's loopback metrics endpoint. Jerd never contacts the
/// public hostname; readiness comes only from `http://127.0.0.1:<port>/ready`.
package enum MetricsEndpoint {
    /// What `lsof` reports about the TCP listeners of the connector process.
    package enum ListenerVerdict: Equatable, Sendable {
        /// No listener yet: cloudflared has not opened its metrics port.
        case none
        /// Exactly `127.0.0.1:<port>`.
        case expected
        /// Another address, another port, or output that cannot be read.
        case unexpected
    }

    package static let lsof = URL(fileURLWithPath: "/usr/sbin/lsof")
    package static let curl = URL(fileURLWithPath: "/usr/bin/curl")
    package static let inspectionTimeout: Duration = .seconds(5)
    package static let readyTimeout: Duration = .seconds(3)

    /// `lsof -nP -a -p <pid> -iTCP -sTCP:LISTEN -Fn`.
    package static func listenersRequest(processID: Int32, directory: URL) -> ProcessRequest {
        ProcessRequest(
            executable: lsof, arguments: ["-nP", "-a", "-p", String(processID), "-iTCP", "-sTCP:LISTEN", "-Fn"],
            workingDirectory: directory)
    }

    /// `lsof -nP -a -iTCP:<port> -sTCP:LISTEN -Fp`.
    package static func ownersRequest(port: UInt16, directory: URL) -> ProcessRequest {
        ProcessRequest(
            executable: lsof, arguments: ["-nP", "-a", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fp"],
            workingDirectory: directory)
    }

    /// A 2-second `curl` of `/ready` that prints only the HTTP status and ignores proxy settings.
    package static func readyRequest(port: UInt16, directory: URL) -> ProcessRequest {
        ProcessRequest(
            executable: curl,
            arguments: [
                "--silent", "--show-error", "--max-time", "2", "--noproxy", "*", "--output", "/dev/null",
                "--write-out", "%{http_code}", "--url", "http://127.0.0.1:\(port)/ready",
            ],
            workingDirectory: directory)
    }

    /// Status 1 with no output means no listener. Otherwise the listener set must be exactly the
    /// loopback metrics address. UDP sockets are allowed, because cloudflared uses QUIC.
    package static func listenerVerdict(_ result: CommandResult, port: UInt16) -> ListenerVerdict {
        if result.status == 1, result.output.isEmpty { return .none }
        guard result.status == 0, let report = ListenerReport.parse(result.output),
            report.addresses == ["127.0.0.1:\(port)"]
        else { return .unexpected }
        return .expected
    }

    /// True when the connector is the only process that listens on its metrics port.
    package static func ownersMatch(_ result: CommandResult, processID: Int32) -> Bool {
        guard result.status == 0, let report = ListenerReport.parse(result.output) else { return false }
        return report.processIDs == [processID]
    }

    /// True only for a successful `curl` that printed exactly `200`.
    package static func isReady(_ result: CommandResult) -> Bool {
        result.status == 0 && result.output == "200"
    }
}
