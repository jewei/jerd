import Testing

@testable import JerdDevKit

@Suite("Test environment and integration groups")
struct TestEnvironmentTests {
    private let webPaths = ["JERD_PHP_CLI": "/r/php", "JERD_PHP_FPM": "/r/php-fpm", "JERD_CADDY": "/r/caddy"]

    @Test("removes every inherited JERD_ variable from default tests")
    func stripsInheritedVariables() throws {
        let inherited = ["PATH": "/usr/bin", "JERD_INTEGRATION": "1", "JERD_UPDATE_INSTALL": "1"]
        #expect(try TestEnvironment.make(inherited: inherited, groups: []) == ["PATH": "/usr/bin"])
    }

    @Test("passes through the variables of a selected group and sets its switches")
    func passesThroughGroupVariables() throws {
        var inherited = webPaths
        inherited["JERD_SECOND_PHP_CLI"] = "/r/php2"
        inherited["JERD_MAIL_RUNTIME"] = "/r/mail"
        let environment = try TestEnvironment.make(inherited: inherited, groups: [.web])
        var expected = webPaths
        expected["JERD_SECOND_PHP_CLI"] = "/r/php2"
        expected["JERD_INTEGRATION"] = "1"
        #expect(environment == expected)
    }

    @Test("sets the group switch even when the user set it to another value")
    func overridesSwitches() throws {
        let inherited = ["JERD_DATABASE_RUNTIMES": "/r/db", "JERD_DATABASE_INTEGRATION": "0"]
        let environment = try TestEnvironment.make(inherited: inherited, groups: [.database])
        #expect(environment["JERD_DATABASE_INTEGRATION"] == "1")
        #expect(environment["JERD_INTEGRATION"] == "1")
    }

    @Test("refuses a group whose required paths are missing or empty")
    func refusesMissingPaths() {
        #expect(
            throws: DevFailure.missingPrerequisite(
                "The web integration tests need JERD_PHP_CLI, JERD_PHP_FPM, JERD_CADDY. "
                    + "Run ./dev runtimes prepare, or set each one to an absolute runtime path.")
        ) {
            try TestEnvironment.make(inherited: ["JERD_PHP_CLI": "/r/php", "JERD_PHP_FPM": ""], groups: [.web])
        }
    }

    @Test("takes the paths of a group from the prepared payloads")
    func usesPreparedPaths() throws {
        let environment = try TestEnvironment.make(inherited: ["JERD_MAIL_RUNTIME": ""], groups: [.mail]) { group in
            group == .mail ? ["JERD_MAIL_RUNTIME": "/p/mail/mailpit-1"] : [:]
        }
        #expect(environment["JERD_MAIL_RUNTIME"] == "/p/mail/mailpit-1")
        #expect(environment["JERD_MAIL_INTEGRATION"] == "1")
    }

    @Test("explicit paths of a group win over the prepared payloads")
    func explicitPathsWin() throws {
        let environment = try TestEnvironment.make(inherited: webPaths, groups: [.web]) { _ in
            Issue.record("The payloads must not be read.")
            return [:]
        }
        #expect(environment["JERD_CADDY"] == "/r/caddy")
    }

    @Test("a missing payload names both ways to provide the runtime")
    func missingPayloadNamesBothWays() {
        #expect(
            throws: DevFailure.missingPrerequisite(
                "The mailpit payload is not prepared. Or set JERD_MAIL_RUNTIME to absolute paths of trusted local runtimes."
            )
        ) {
            try TestEnvironment.make(inherited: [:], groups: [.mail]) { _ in
                throw DevFailure.missingPrerequisite("The mailpit payload is not prepared.")
            }
        }
    }

    @Test("parses a group list in a fixed order without duplicates")
    func parsesGroupList() throws {
        #expect(try IntegrationGroup.parseList("storage, web,storage") == [.web, .storage])
    }

    @Test("refuses an unknown or empty group list as a usage error")
    func refusesBadGroupList() {
        #expect(throws: DevFailure.self) { try IntegrationGroup.parseList("web,cache") }
        #expect(throws: DevFailure.self) { try IntegrationGroup.parseList(",") }
        do {
            _ = try IntegrationGroup.parseList("cache")
        } catch let failure as DevFailure {
            #expect(failure.status == .usage)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("every group documents only JERD_ variables")
    func groupsUseOnlyJerdVariables() {
        for group in IntegrationGroup.allCases {
            let names = group.requiredVariables + group.optionalVariables + Array(group.switchVariables.keys)
            #expect(names.allSatisfy { $0.hasPrefix(TestEnvironment.prefix) })
        }
    }
}
