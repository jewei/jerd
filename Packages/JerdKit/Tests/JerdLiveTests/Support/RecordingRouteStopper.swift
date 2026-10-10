import Foundation

@testable import JerdLive

/// Records each check of the local tunnel routes, with the served sites that it got.
actor RecordingRouteStopper: LocalRouteStopping {
    private(set) var checks: [[UUID: String]] = []

    func stopRoutesToUnservedSites(_ served: [UUID: String]) {
        checks.append(served)
    }
}
