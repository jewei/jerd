import Foundation

/// Shared defaults with explicit SAPI differences. The CLI can run without the app.
public enum PHPConfigurationPolicy {
    public static let commonINI = """
    [PHP]
    date.timezone = UTC
    expose_php = Off
    log_errors = On

    """
    public static let fpmINI = commonINI + """
    memory_limit = 256M
    upload_max_filesize = 32M
    post_max_size = 40M
    max_execution_time = 30
    display_errors = Off
    cgi.fix_pathinfo = 0
    [opcache]
    opcache.enable = 1
    opcache.validate_timestamps = 1
    opcache.revalidate_freq = 0

    """
    public static let cliINI = commonINI + """
    memory_limit = -1
    max_execution_time = 0
    display_errors = stderr
    [opcache]
    opcache.enable_cli = 0

    """

    public struct CLIConfiguration: Sendable {
        public let arguments: [String]
        public let environment: [String: String]
    }

    public static func cli(arguments: [String], command: String = "php", directory: URL,
                           environment: [String: String]) throws -> CLIConfiguration {
        let scan = directory.appendingPathComponent("empty-ini")
        try PrivateFiles.directory(directory)
        try PrivateFiles.directory(scan)
        var additions: [String: String] = [:]
        if environment["PHP_INI_SCAN_DIR"] == nil { additions["PHP_INI_SCAN_DIR"] = scan.path }
        // PHPRC and PHP_INI_SCAN_DIR are explicit user inputs in a terminal.
        // Companion arguments belong to the script, not to the PHP interpreter.
        if environment["PHPRC"] != nil || (command == "php" && hasINISelection(arguments)) {
            return CLIConfiguration(arguments: [], environment: additions)
        }
        let file = directory.appendingPathComponent("cli.ini")
        let data = Data(cliINI.utf8)
        if try !FileManager.default.fileExists(atPath: file.path) || PrivateFiles.read(file, limit: 65_536) != data {
            try PrivateFiles.write(data, to: file)
        }
        return CLIConfiguration(arguments: ["-c", file.path], environment: additions)
    }

    static func hasINISelection(_ arguments: [String]) -> Bool {
        var index = 0
        while index < arguments.count {
            let value = arguments[index]
            if value == "--" || !value.hasPrefix("-") { break }
            if value == "-n" || value == "--no-php-ini" || value.hasPrefix("-c") || value == "--php-ini" || value.hasPrefix("--php-ini=") { return true }
            let consumesValue = ["-r", "-R", "-B", "-E", "-f", "-F", "-d", "-z", "-S", "-t",
                                 "--run", "--process-code", "--process-begin", "--process-end", "--file", "--process-file",
                                 "--define", "--zend-extension", "--server", "--docroot"].contains(value)
            index += consumesValue ? 2 : 1
        }
        return false
    }
}
