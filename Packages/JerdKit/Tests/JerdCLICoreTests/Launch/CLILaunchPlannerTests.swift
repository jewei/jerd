import Foundation
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
            userArguments: arguments.map { Array($0.utf8) }, environment: CLIEnvironment(environment),
            iniEnvironment: iniEnvironment, binDirectory: Self.bin)
    }

    /// The lexical form only, so the pure rule does not depend on this Mac's folders.
    private static let lexical: SearchPath.Canonicalizer = { SearchPath.lexical($0) }

    private func searchPath(_ path: String?, canonicalize: @escaping SearchPath.Canonicalizer = lexical) -> String {
        let result = SearchPath.prepending(
            Array(Self.bin.utf8), to: path.map { Array($0.utf8) }, canonicalize: canonicalize)
        return String(decoding: result, as: UTF8.self)
    }

    @Test(arguments: [
        (CLICommand.php, nil as String?, ["/php/8.5/php", "-c", "/cli.ini", "-v"]),
        (.composer, "/c/composer.phar", ["/php/8.5/php", "-c", "/cli.ini", "/c/composer.phar", "-v"]),
        (.laravel, "/l/bin/laravel", ["/php/8.5/php", "-c", "/cli.ini", "/l/bin/laravel", "-v"]),
    ])
    func scriptGoesBeforeTheUserArguments(command: CLICommand, script: String?, expected: [String]) throws {
        let plan = try CLILaunchPlanner.plan(request(command, script: script), canonicalize: Self.lexical)
        #expect(plan.executable == "/php/8.5/php")
        #expect(plan.argumentText == expected)
    }

    @Test func userINIGivesNoINIArguments() throws {
        let plan = try CLILaunchPlanner.plan(request(.php, ini: [], arguments: ["-n", "-r", "echo 1;"]))
        #expect(plan.argumentText == ["/php/8.5/php", "-n", "-r", "echo 1;"])
    }

    @Test func userArgumentsPassUnchangedOnce() throws {
        let arguments = ["--", "-c", "a b", "", "ünïcode", "$HOME"]
        let plan = try CLILaunchPlanner.plan(request(.composer, script: "/c.phar", arguments: arguments))
        #expect(Array(plan.argumentText.suffix(arguments.count)) == arguments)
        #expect(plan.arguments.count == 4 + arguments.count)
    }

    @Test func userArgumentBytesThatAreNotUTF8StayTheSame() throws {
        let raw = CLILaunchRequest(
            command: .php, phpExecutable: "/php/8.5/php", iniArguments: [], companionScript: nil,
            userArguments: [[0xFF, 0xFE]],
            environment: CLIEnvironment(entries: [[0x50, 0x41, 0x54, 0x48, 0x3D, 0xE9]]),
            iniEnvironment: [:], binDirectory: Self.bin)
        let plan = try CLILaunchPlanner.plan(raw, canonicalize: Self.lexical)
        #expect(plan.arguments.last == [0xFF, 0xFE])
        #expect(plan.environment.value("PATH") == Array(Self.bin.utf8) + [0x3A, 0xE9])
    }

    @Test func environmentGetsTheINIVariablesAndPathAndKeepsTheRest() throws {
        let plan = try CLILaunchPlanner.plan(
            request(.php, environment: ["PATH": "/usr/bin:/bin", "HOME": "/Users/u"]), canonicalize: Self.lexical)
        #expect(
            plan.environment
                == CLIEnvironment([
                    "HOME": "/Users/u", "PHP_INI_SCAN_DIR": "/empty", "PATH": "\(Self.bin):/usr/bin:/bin",
                ]))
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
        ("\(bin)/:/usr/bin", "\(bin):/usr/bin"),
        ("/Users/u//Library/Application Support/Jerd/./bin:/usr/bin", "\(bin):/usr/bin"),
    ])
    func pathStartsWithJerdBinExactlyOnce(path: String?, expected: String) {
        #expect(searchPath(path) == expected)
    }

    @Test func nestedCallsDoNotGrowPath() {
        var path: String? = "/usr/local/bin:/usr/bin"
        for _ in 0..<5 { path = searchPath(path) }
        #expect(path == "\(Self.bin):/usr/local/bin:/usr/bin")
    }

    @Test func entryThroughASymbolicLinkIsTheSameFolder() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let real = try directory.folder("real/bin")
        let alias = directory.path("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real.deletingLastPathComponent())
        // The temporary folder is below /private; the same folder without it is a link form.
        let short = real.path.hasPrefix("/private/") ? String(real.path.dropFirst("/private".count)) : real.path
        let path = "\(short):\(alias.path)/bin/:/usr/bin"
        let result = SearchPath.prepending(Array(real.path.utf8), to: Array(path.utf8))
        #expect(String(decoding: result, as: UTF8.self) == "\(real.path):/usr/bin")
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
