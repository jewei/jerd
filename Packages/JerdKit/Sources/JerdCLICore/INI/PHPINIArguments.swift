/// Finds the PHP CLI options that choose the INI file: `-n`, `--no-php-ini`, `-c…`, and `--php-ini…`.
///
/// Only options before the script name or `--` count. An option that takes a value consumes the
/// next argument, so `-d -n` sets an INI entry named `-n` and selects nothing.
public enum PHPINIArguments {
    /// The PHP CLI options that take the next argument as their value.
    public static let valueOptions: Set<String> = [
        "-r", "-R", "-B", "-E", "-f", "-F", "-d", "-z", "-S", "-t",
        "--run", "--process-code", "--process-begin", "--process-end", "--file", "--process-file",
        "--define", "--zend-extension", "--server", "--docroot",
    ]

    /// True when `arguments` (without `argv[0]`) choose or disable the INI file.
    public static func selectINI(_ arguments: [String]) -> Bool {
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            if argument == "--" || !argument.hasPrefix("-") { return false }
            if selectsINI(argument) { return true }
            index += valueOptions.contains(argument) ? 2 : 1
        }
        return false
    }

    private static func selectsINI(_ argument: String) -> Bool {
        argument == "-n" || argument == "--no-php-ini" || argument.hasPrefix("-c")
            || argument == "--php-ini" || argument.hasPrefix("--php-ini=")
    }
}
