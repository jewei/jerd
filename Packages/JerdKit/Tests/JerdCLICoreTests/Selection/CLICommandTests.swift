import JerdFoundation
import Testing

@testable import JerdCLICore

@Suite struct CLICommandTests {
    @Test(arguments: [
        ("php", CLICommand.php),
        ("/Users/u/Library/Application Support/Jerd/bin/composer", .composer),
        ("bin/laravel", .laravel),
        ("/usr/local/bin/php/", .php),
    ])
    func linkNameSelectsTheCommand(name: String, command: CLICommand) throws {
        #expect(try CLICommand(invocationName: name) == command)
    }

    @Test(arguments: ["JerdCLI", "", "/", "php8", "PHP", "composer.phar"])
    func otherNamesAreRefused(name: String) {
        #expect(
            throws: JerdError.invalid(
                "Run Jerd's launcher as php, composer, or laravel. Set up these commands in Jerd first.")
        ) { try CLICommand(invocationName: name) }
    }

    @Test func onlyComposerAndLaravelRunACompanionScript() {
        #expect(!CLICommand.php.runsCompanionScript)
        #expect(CLICommand.composer.runsCompanionScript)
        #expect(CLICommand.laravel.runsCompanionScript)
    }
}
