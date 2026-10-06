import Testing

@testable import JerdCLICore

@Suite struct PHPINIArgumentsTests {
    @Test(arguments: [
        ["-n"], ["--no-php-ini"], ["-c", "/custom/php.ini"], ["-c/custom/php.ini"], ["-c"],
        ["--php-ini", "/x"], ["--php-ini=/custom/php.ini"],
        ["-d", "memory_limit=1G", "-n"], ["-f", "x", "-n"], ["-dmemory_limit=1G", "-n"],
        ["--define", "a=b", "-c", "/x"], ["-v", "-n"],
    ])
    func optionsBeforeTheScriptSelectTheINI(arguments: [String]) {
        #expect(PHPINIArguments.selectINI(arguments))
    }

    @Test(arguments: [
        [], ["-r", "-n"], ["script.php", "-n"], ["--", "-c"], ["-d", "-n"], ["-f", "-c"],
        ["-d", "memory_limit=123M", "script.php"], ["--define", "-n"], ["-S", "-n"], ["-t", "-c"],
        ["--php-inifile"], ["-v"], ["artisan", "--php-ini=/x"], ["--run", "-n"], ["-z", "-n"],
    ])
    func valuesScriptsAndTheSeparatorSelectNothing(arguments: [String]) {
        #expect(!PHPINIArguments.selectINI(arguments))
    }

    @Test func everyValueOptionConsumesTheNextArgument() {
        for option in PHPINIArguments.valueOptions {
            #expect(!PHPINIArguments.selectINI([option, "-n"]), "\(option)")
            #expect(PHPINIArguments.selectINI([option, "value", "-n"]), "\(option)")
        }
    }
}
