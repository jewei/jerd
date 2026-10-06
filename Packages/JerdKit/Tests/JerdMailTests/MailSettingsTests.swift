import Foundation
import JerdFoundation
import JerdServiceKitTestSupport
import Testing

@testable import JerdMail

@Suite struct MailSettingsTests {
    static let runtime = MailRuntime(
        id: "mailpit-1.31.3-arm64", version: "1.31.3",
        path: "/Users/me/Library/Application Support/Jerd/mail-runtimes/mailpit-1.31.3-arm64")

    @Test func settingsOfOlderBuildsDecodeAndEncodeToTheSameBytes() throws {
        let bytes = try golden("mail-settings.json")
        let settings = try JSONDecoder().decode(MailSettings.self, from: bytes)
        try settings.validate()
        #expect(settings == MailSettings(runtime: Self.runtime, ports: MailPorts(smtp: 1_026, web: 8_026)))
        #expect(try JSONFileFormat.settings.makeEncoder().encode(settings) == bytes)
    }

    @Test func settingsWithoutARuntimeLeaveTheRuntimeKeyOut() throws {
        let bytes = try golden("mail-settings-without-runtime.json")
        let settings = try JSONDecoder().decode(MailSettings.self, from: bytes)
        #expect(settings == MailSettings())
        #expect(try JSONFileFormat.settings.makeEncoder().encode(MailSettings()) == bytes)
    }

    @Test(arguments: ["schemaVersion", "smtpPort", "webPort"])
    func everyRequiredKeyIsRequired(_ key: String) throws {
        let object = try jsonObject(try golden("mail-settings.json")).mutableCopy() as! NSMutableDictionary
        object.removeObject(forKey: key)
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(MailSettings.self, from: data) }
    }

    @Test func theRuntimeMarkerOfOlderBuildsDecodes() throws {
        let bytes = try golden("mail-runtime.json")
        #expect(try JSONDecoder().decode(MailRuntime.self, from: bytes) == Self.runtime)
        let encoded = try JSONFileFormat.compact.makeEncoder().encode(Self.runtime)
        #expect(try jsonObject(encoded) == jsonObject(bytes))
    }

    @Test(arguments: [
        MailPorts(smtp: 1_025, web: 1_025), MailPorts(smtp: 80, web: 8_025), MailPorts(smtp: 1_025, web: 1_023),
    ])
    func portsMustDifferAndBeUnprivileged(_ ports: MailPorts) {
        #expect(throws: MailMessages.settingsInvalid) { try MailSettings(ports: ports).validate() }
    }

    @Test func anUnsupportedVersionIsRejected() {
        var settings = MailSettings()
        settings.schemaVersion = 2
        #expect(throws: MailMessages.settingsInvalid) { try settings.validate() }
    }

    @Test(arguments: [
        MailRuntime(id: "", version: "1.31.3", path: "/runtime"),
        MailRuntime(id: "mailpit", version: "1.31/3", path: "/runtime"),
        MailRuntime(id: "mailpit", version: "1.31.3", path: "relative/runtime"),
        MailRuntime(id: "mailpit", version: "1.31.3", path: "/runtime\nnext"),
    ])
    func anInvalidRuntimeRecordIsRejected(_ runtime: MailRuntime) {
        #expect(throws: MailMessages.runtimeRecordInvalid) { try MailSettings(runtime: runtime).validate() }
    }

    @Test func laravelEnvironmentUsesTheLocalSMTPPortWithoutCredentials() {
        let settings = MailSettings(runtime: Self.runtime, ports: MailPorts(smtp: 2_525, web: 8_026))
        let expected =
            "MAIL_MAILER=smtp\nMAIL_SCHEME=null\nMAIL_URL=null\nMAIL_HOST=127.0.0.1\nMAIL_PORT=2525\n"
            + "MAIL_USERNAME=null\nMAIL_PASSWORD=null\nMAIL_ENCRYPTION=null\n"
            + "MAIL_FROM_ADDRESS=\"hello@jerd.test\"\nMAIL_FROM_NAME=\"Jerd\"\n"
        #expect(settings.laravelEnvironment == expected)
        #expect(settings.inboxURL.absoluteString == "http://127.0.0.1:8026/")
    }
}
