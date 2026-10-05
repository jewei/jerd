import Foundation
import JerdFoundation
import JerdProcess

/// What the engine owns during one run. It grows step by step, so a failed start stops exactly
/// what it started.
struct ActiveRun: Sendable {
    let id = EngineRunID()
    let layout: RunLayout
    var lock: InstanceLock?
    var ownsSocketDirectory = false
    /// Every started process in start order: the FPM masters, then Caddy.
    var started: [ProcessToken] = []
    /// The FPM masters, for pings and listener checks.
    var pools: [(token: ProcessToken, socket: URL)] = []
    var caddy: ProcessToken?

    init(layout: RunLayout) {
        self.layout = layout
    }

    /// The stop order: the reverse start order, so Caddy stops before the pools it uses.
    var stopOrder: [ProcessToken] { started.reversed() }
}
