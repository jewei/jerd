import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit

/// A service definition with scripted steps. It records "prepare", "setup", and "complete".
struct FakeServiceDefinition: ServiceDefinition {
    var profile: ServiceProfile
    var versionProbe: VersionProbe
    var plan: LaunchPlan
    var setupPlan: LaunchPlan?
    var prepareError: JerdError?
    var completeError: JerdError?
    let events: EventLog

    func prepareStart(_ tools: StartTools) async throws -> LaunchPlan {
        events.add("prepare")
        if let prepareError { throw prepareError }
        if let setupPlan {
            events.add("setup")
            try await tools.runSetupPhase(setupPlan)
        }
        return plan
    }

    func completeStart() async throws {
        events.add("complete")
        if let completeError { throw completeError }
    }

    /// The messages of the fake service.
    static let messages = ServiceMessages(
        busy: "The fake service is busy.", alreadyHasProcess: "The fake service already has a process.",
        lockUnavailable: "Cannot lock the fake service.", lockBusy: "Another Jerd process uses the fake service.",
        couldNotStart: "The fake process could not start.", exitedBeforeReady: "The fake service exited early.",
        exitedDuringCheck: "The fake service exited during its check.", exited: "The fake process exited.",
        logUnavailable: "Open the fake log.")
}
