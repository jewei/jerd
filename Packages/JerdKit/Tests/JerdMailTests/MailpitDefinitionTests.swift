import Foundation
import JerdFoundation
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@testable import JerdMail

@Suite struct MailpitDefinitionTests {
    static let layout = DataLayout(root: URL(fileURLWithPath: "/Users/me/Library/Application Support/Jerd"))

    static func definition(ports: MailPorts = MailPorts(smtp: 1_026, web: 8_026)) -> MailpitDefinition {
        MailpitDefinition(
            runtime: MailSettingsTests.runtime, ports: ports, layout: layout.mail, dataRoot: layout.root,
            server: FakeMailServer())
    }

    @Test func mailpitGetsExactLoopbackArgumentsAndACleanEnvironment() {
        let request = Self.definition().serverRequest
        #expect(request.executable.path == MailSettingsTests.runtime.path + "/mailpit")
        #expect(
            request.arguments == [
                "--database", "/Users/me/Library/Application Support/Jerd/mail/inbox/messages.sqlite",
                "--smtp", "127.0.0.1:1026", "--listen", "127.0.0.1:8026",
                "--allowed-hosts", "127.0.0.1,localhost", "--label", "Jerd", "--max", "0",
                "--disable-version-check", "--smtp-disable-rdns", "--block-remote-css-and-fonts",
            ])
        #expect(request.environment.isEmpty)
        #expect(request.workingDirectory.path == "/Users/me/Library/Application Support/Jerd/mail")
    }

    @Test func theProfileNamesTheMailRecordPortsAndMessages() {
        let profile = Self.definition().profile
        #expect(profile.name == "Mailpit")
        #expect(profile.runtimeID == "mailpit-1.31.3-arm64")
        #expect(profile.record == Self.layout.mail.record)
        #expect(profile.ports == [1_026, 8_026])
        #expect(profile.stopSignal == SIGTERM)
        #expect(profile.messages.lockBusy == "Another Jerd process is using this mail inbox.")
        #expect(
            ServiceMessages.stopTimedOut(name: profile.name, timeout: .seconds(30))
                == "Mailpit did not stop within 30 seconds. Its process is still tracked. "
                + "Retry Stop; Jerd did not force it to exit.")
    }

    @Test func theVersionCommandSkipsTheReleaseCheck() {
        let probe = Self.definition().versionProbe
        #expect(probe.request.arguments == ["version", "--no-release-check"])
        #expect(probe.mismatchMessage == "The Mailpit executable does not match the saved version.")
    }

    @Test func aVersionInsideTheRuntimePathDoesNotPassTheVersionCheck() {
        let rule = Self.definition().versionProbe.rule
        let path = MailSettingsTests.runtime.executable.path
        #expect(rule.matches("\(path) v1.31.3 compiled with go1.27.1 on darwin/arm64\n"))
        #expect(rule.matches("\(path) 1.31.3\n"))
        #expect(!rule.matches("\(path) v2.0.0 compiled with go1.27.1 on darwin/arm64\n"))
        #expect(!rule.matches("\(path) v1.31.30\n"))
        #expect(!rule.matches("/other/mailpit v1.31.3\n"))
    }
}
