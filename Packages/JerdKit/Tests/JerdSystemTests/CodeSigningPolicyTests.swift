import JerdFoundation
import Testing

@testable import JerdSystem

@Suite struct CodeSigningPolicyTests {
    @Test func buildsTheExactRequirementText() throws {
        let text = try CodeSigningPolicy.requirement(identifier: "dev.jerd.app", teamID: "ABCDE12345")
        #expect(
            text == "anchor apple generic and identifier \"dev.jerd.app\" and certificate leaf[subject.OU] = "
                + "\"ABCDE12345\" and !entitlement[\"com.apple.security.get-task-allow\"] exists")
        #expect(
            try CodeSigningPolicy.requirement(identifier: "dev.jerd.helper", teamID: "ABCDE12345").contains(
                "\"dev.jerd.helper\""))
    }

    @Test(arguments: [
        ("another.app", "ABCDEFGHIJ"), ("dev.jerd.app", "\" or true"), ("dev.jerd.app", "abcdefghij"),
        ("dev.jerd.app", "ABCDEFGHI"), ("dev.jerd.app", "ABCDEFGHIJK"), ("dev.jerd.app", "ÄBCDEFGHIJ"),
    ])
    func refusesForeignIdentifiersAndInvalidTeams(identifier: String, team: String) {
        #expect(throws: JerdError.invalid("A valid Apple signing team is required for system setup.")) {
            try CodeSigningPolicy.requirement(identifier: identifier, teamID: team)
        }
    }

}
