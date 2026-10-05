import JerdFoundation
import JerdSystem
import Testing

@testable import JerdHelperCore

@Suite struct HelperLaunchPlanTests {
    private let team = { "ABCDE12345" }

    @Test func checkSigningPrintsTheTeamWithoutRoot() throws {
        let plan = try HelperLaunchPlan.decide(
            arguments: ["JerdHelper", "--check-signing"], effectiveUserID: 501, teamID: team)
        #expect(plan == .printSigning(message: "Jerd helper requires the signed app from team ABCDE12345."))
    }

    @Test func listeningNeedsRoot() throws {
        #expect(throws: JerdError.unavailable("Launch this helper through Jerd's approved SMAppService setup.")) {
            try HelperLaunchPlan.decide(arguments: ["JerdHelper"], effectiveUserID: 501, teamID: team)
        }
        let plan = try HelperLaunchPlan.decide(arguments: ["JerdHelper"], effectiveUserID: 0, teamID: team)
        #expect(
            plan
                == .listen(
                    requirement: try CodeSigningPolicy.requirement(identifier: "dev.jerd.app", teamID: "ABCDE12345")))
    }

    @Test func otherArgumentsDoNotSkipTheRootCheck() {
        #expect(throws: JerdError.self) {
            try HelperLaunchPlan.decide(
                arguments: ["JerdHelper", "--check-signing", "x"], effectiveUserID: 501, teamID: team)
        }
    }

    @Test func anUnsignedBuildCannotStart() {
        #expect(throws: JerdError.unavailable("unsigned")) {
            try HelperLaunchPlan.decide(arguments: ["JerdHelper", "--check-signing"], effectiveUserID: 0) {
                throw JerdError.unavailable("unsigned")
            }
        }
    }
}
