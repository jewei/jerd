import Foundation
import JerdFoundation
import JerdProcess

/// One server process to start: the request, the exact loopback listeners it must own, how to
/// tell that it is ready, and what to remove after it stops.
public struct LaunchPlan: Sendable {
    public var request: ProcessRequest
    /// The loopback TCP ports that the process must own, and no other listener. Empty for a
    /// socket-only setup phase.
    public var ports: Set<UInt16>
    public var readiness: ReadinessCheck
    /// Secrets that never appear in messages and log tails.
    public var secrets: [String]
    /// Files and folders of this launch only (for example a socket folder). They are removed when
    /// the process has stopped, or when the launch fails before a process is owned.
    public var temporaryItems: [URL]
    /// Runs once when the launch ends: after its process stopped (by a Stop, after an exit, or
    /// after a reap outside Jerd), or when the launch fails before a process is owned. It runs
    /// after the temporary items are removed. Use it to release resources that are not files,
    /// for example a URL session. It runs on the instance actor, so it must not block.
    public var didStop: (@Sendable () -> Void)?

    public init(
        request: ProcessRequest, ports: Set<UInt16>, readiness: ReadinessCheck, secrets: [String] = [],
        temporaryItems: [URL] = [], didStop: (@Sendable () -> Void)? = nil
    ) {
        self.request = request
        self.ports = ports
        self.readiness = readiness
        self.secrets = secrets
        self.temporaryItems = temporaryItems
        self.didStop = didStop
    }

    /// Removes the temporary items. A missing item is not an error.
    ///
    /// A failed removal is not reported: the items are private to this launch and hold no user
    /// data, and the next launch uses new names.
    public func removeTemporaryItems() {
        for item in temporaryItems where FileProbe.presence(at: item).mayExist {
            try? FileManager.default.removeItem(at: item)
        }
    }

    /// Ends the launch: removes the temporary items, then runs `didStop`. The kit calls it once
    /// for each launch.
    func end() {
        removeTemporaryItems()
        didStop?()
    }
}
