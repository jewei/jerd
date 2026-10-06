import JerdFoundation
import Testing

@testable import JerdCLICore

@Suite struct CLILaunchPlannerTests {
    private static let bin = "/Users/u/Library/Application Support/Jerd/bin"

    private func request(
        _ command: CLICommand, script: String? = nil, ini: [String] = ["-c", "/cli.ini"],
        arguments: [String] = ["-v"], environment: [String: String] = ["PATH": "/usr/bin:/bin"],
        iniEnvironment: [String: String] = ["PHP_INI_SCAN_DIR": "/empty"], php: String = "/php/8.5/php"
    ) -> CLILaunchRequest {
        CLILaunchRequest(
            command: command, phpExecutable: php, iniArguments: ini, companionScript: script,
            userArguments: arguments, environment: environment, iniEnvironment: iniEnvironment,
            binDirectory: Self.bin)
    }

    @Test(arguments: [
        (CLICommand.php, nil as String?, ["/php/8.5/php", "-c", "/cli.ini", "-v"]),
        (.composer, "/c/composer.phar", ["/php/8.5/php", "-c", "/cli.ini", "/c/composer.phar", "-v"]),
        (.laravel, "/l/bin/laravel", ["/php/8.5/php", "-c", "/cli.ini", "/l/bin/laravel", "-v"]),
    ])
    func scriptGoesBeforeTheUserArguments(command: CLICommand, script: String?, expected: [String]) throws {
        let plan = try CLILaunchPlanner.plan(request(command, script: script))
        #expect(plan.executable == "/php/8.5/php")
        #expect(plan.arguments == expected)
    }

    @Test func userINIGivesNoINIArguments() throws {
        let plan = try CLILaunchPlanner.plan(request(.php, ini: [], arguments: ["-n", "-r", "echo 1;"]))
        #expect(plan.arguments == ["/php/8.5/php", "-n", "-r", "echo 1;"])
    }

    @Test func userArgumentsPassUnchangedOnce() throws {
        let arguments = ["--", "-c", "a b", "", "ünïcode", "$HOME"]
        let plan = try CLILaunchPlanner.plan(request(.composer, script: "/c.phar", arguments: arguments))
        #expect(Array(plan.arguments.suffix(arguments.count)) == arguments)
        #expect(plan.arguments.count == 4 + arguments.count)
    }

    @Test func environmentChangesAreTheINIVariablesAndPath() throws {
        let plan = try CLILaunchPlanner.plan(request(.php))
        #expect(plan.environmentChanges == ["PHP_INI_SCAN_DIR": "/empty", "PATH": "\(Self.bin):/usr/bin:/bin"])
        let applied = plan.environment(applyingTo: ["PATH": "/usr/bin:/bin", "HOME": "/Users/u"])
        #expect(applied["HOME"] == "/Users/u")
        #expect(applied["PATH"] == "\(Self.bin):/usr/bin:/bin")
    }

    @Test(arguments: [
        (nil as String?, "\(bin):/usr/bin:/bin"),
        ("", "\(bin):/usr/bin:/bin"),
        ("/usr/bin", "\(bin):/usr/bin"),
        ("\(bin):/usr/bin", "\(bin):/usr/bin"),
        ("/opt/bin:\(bin):/usr/bin", "\(bin):/opt/bin:/usr/bin"),
        ("\(bin):\(bin):/usr/bin:\(bin)", "\(bin):/usr/bin"),
        ("/usr/bin::/bin", "\(bin):/usr/bin::/bin"),
        ("\(bin)", "\(bin)"),
    ])
    func pathStartsWithJerdBinExactlyOnce(path: String?, expected: String) {
        #expect(CLILaunchPlanner.searchPath(prepending: Self.bin, to: path) == expected)
    }

    @Test func nestedCallsDoNotGrowPath() {
        var path: String? = "/usr/local/bin:/usr/bin"
        for _ in 0..<5 { path = CLILaunchPlanner.searchPath(prepending: Self.bin, to: path) }
        #expect(path == "\(Self.bin):/usr/local/bin:/usr/bin")
    }

    @Test func relativePHPPathIsRefused() {
        #expect(throws: JerdError.invalid("The PHP runtime path must be absolute: php")) {
            try CLILaunchPlanner.plan(request(.php, php: "php"))
        }
    }

    @Test(arguments: [(CLICommand.php, "/c.phar" as String?), (.composer, nil), (.laravel, nil)])
    func companionScriptMustFitTheCommand(command: CLICommand, script: String?) {
        #expect(throws: JerdError.self) { try CLILaunchPlanner.plan(request(command, script: script)) }
    }
}
