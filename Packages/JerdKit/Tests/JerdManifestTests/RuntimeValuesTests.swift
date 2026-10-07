import JerdManifest
import Testing

@Suite struct RuntimeValuesTests {
    @Test func versionsOrderNumericallyAndPadToFourParts() throws {
        #expect(try #require(RuntimeVersion("8.10.2")) > #require(RuntimeVersion("8.8.3")))
        #expect(RuntimeVersion("v8.5.11") == RuntimeVersion("8.5.11.0"))
        #expect(RuntimeVersion("2026.9.3")?.components == [2026, 9, 3, 0])
        #expect(RuntimeVersion("8.5.11")?.prefix(2) == "8.5")
        #expect(RuntimeVersion("v8.5")?.description == "8.5.0.0")
    }

    @Test(arguments: [
        "8.6.0RC1", "8.6.0-beta", "../8.6", "8..6", "8.6 ", "99999999999.1", "8", "1.2.3.4.5", "", "v", "vv8.5",
        "8.100000", "8.-1", "+8.5", "٨.٥",
    ])
    func unstableOrMalformedVersionsAreRefused(_ text: String) {
        #expect(RuntimeVersion(text) == nil)
    }

    @Test func kindOrderTitlesAndRawValuesAreStable() {
        #expect(
            RuntimeKind.allCases.map(\.rawValue) == [
                "php", "caddy", "composer", "laravel", "mysql", "postgresql", "redis", "mailpit", "rustfs",
                "cloudflared",
            ])
        #expect(
            RuntimeKind.allCases.map(\.title) == [
                "PHP", "Caddy", "Composer", "Laravel installer", "MySQL", "PostgreSQL", "Redis", "Mailpit", "RustFS",
                "Cloudflare Tunnel",
            ])
        #expect(RuntimeKind.allCases.filter(\.isPHPScript) == [.composer, .laravel])
    }

    @Test func everyBundledKindHasOneGroupAndCloudflaredHasNone() {
        #expect(PayloadGroup.development.kinds == [.php, .caddy, .composer, .laravel])
        #expect(PayloadGroup.database.kinds == [.mysql, .postgresql, .redis])
        #expect(PayloadGroup.mail.kinds == [.mailpit])
        #expect(PayloadGroup.storage.kinds == [.rustfs])
        #expect(PayloadGroup(kind: .cloudflared) == nil)
    }

    @Test func architectureNamesMatchPublisherFileNames() {
        #expect(CPUArchitecture.arm64.goName == "arm64")
        #expect(CPUArchitecture.intel.goName == "amd64")
        #expect(CPUArchitecture.arm64.rustName == "aarch64")
        #expect(CPUArchitecture.intel.rustName == "x86_64")
    }

    @Test(arguments: ["php-8.5.11-arm64", "a", "A.b-1", String(repeating: "x", count: 100)])
    func safeIdentifiersAreAccepted(_ text: String) {
        #expect(PayloadIdentifier.isValid(text))
    }

    @Test(arguments: [
        "", ".", "..", "-a", ".hidden", "../escape", "a/b", "a b", "a_b", String(repeating: "x", count: 101),
    ])
    func unsafeIdentifiersAreRefused(_ text: String) {
        #expect(!PayloadIdentifier.isValid(text))
    }
}
