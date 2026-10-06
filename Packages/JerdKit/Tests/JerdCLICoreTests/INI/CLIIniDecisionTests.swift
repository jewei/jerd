import Testing

@testable import JerdCLICore

@Suite struct CLIIniDecisionTests {
    typealias Choice = CLIIniDecision.Choice

    @Test(arguments: [
        (CLICommand.php, [String](), [String: String](), Choice.jerdINIWithLocalCA),
        (.php, ["-n"], [:], .userINI),
        (.php, ["-c", "/x.ini"], [:], .userINI),
        (.php, ["--php-ini=/x.ini"], [:], .userINI),
        (.php, ["-d", "memory_limit=1G"], [:], .jerdINIWithLocalCA),
        (.php, ["script.php", "-n"], [:], .jerdINIWithLocalCA),
        (.php, [], ["PHPRC": "/etc/php"], .userINI),
        (.composer, ["-n"], [:], .jerdINIWithLocalCA),
        (.laravel, ["-c", "x"], [:], .jerdINIWithLocalCA),
        (.composer, [], ["PHPRC": "/etc/php"], .userINI),
        (.php, [], ["SSL_CERT_FILE": "/ca.pem"], .jerdINIWithUserTrust),
        (.php, [], ["SSL_CERT_DIR": "/certs"], .jerdINIWithUserTrust),
        (.composer, [], ["CURL_CA_BUNDLE": "/ca.pem"], .jerdINIWithUserTrust),
        (.php, ["-n"], ["SSL_CERT_FILE": "/ca.pem"], .userINI),
        (.php, [], ["PHPRC": "/etc/php", "CURL_CA_BUNDLE": "/ca.pem"], .userINI),
        (.php, [], ["PHP_INI_SCAN_DIR": "/fragments"], .jerdINIWithLocalCA),
    ])
    func oneRuleChoosesTheINIAndTheTrust(
        command: CLICommand, arguments: [String], environment: [String: String], expected: Choice
    ) {
        let decision = CLIIniDecision(command: command, arguments: arguments, environment: environment)
        #expect(decision.choice == expected)
        #expect(decision.wantsLocalCA == (expected == .jerdINIWithLocalCA))
    }

    @Test(arguments: [
        ([String: String](), true),
        (["PHP_INI_SCAN_DIR": "/fragments"], false),
        (["PHP_INI_SCAN_DIR": ""], false),
        (["PHPRC": "/etc/php"], true),
    ])
    func emptyScanFolderAppliesUnlessTheUserSetOne(environment: [String: String], expected: Bool) {
        let decision = CLIIniDecision(command: .php, arguments: [], environment: environment)
        #expect(decision.usesEmptyScanDirectory == expected)
    }
}
