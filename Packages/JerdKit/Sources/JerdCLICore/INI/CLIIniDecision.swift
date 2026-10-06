/// The one rule for the INI file and the TLS trust of a command.
///
/// Rules, in order:
/// 1. `PHPRC`, or (`php` only) `-n`, `-c`, or `--php-ini` before the script: the user chose the INI.
///    Jerd adds no `-c` and no CA. `composer` and `laravel` pass INI options to their script.
/// 2. `SSL_CERT_FILE`, `SSL_CERT_DIR`, or `CURL_CA_BUNDLE`: the user chose the trust. Jerd's INI
///    applies without the local CA.
/// 3. Otherwise Jerd's INI applies with the local CA when the CA is available and trusted.
///
/// `PHP_INI_SCAN_DIR` points to Jerd's empty folder unless the user set it. `-d` options always
/// apply after the INI, so they stay effective.
public struct CLIIniDecision: Equatable, Sendable {
    /// Where the INI and the TLS trust of the command come from.
    public enum Choice: Equatable, Sendable {
        /// The user's INI selection. Jerd adds no `-c`.
        case userINI
        /// Jerd's INI without the local CA, because the user set trust variables.
        case jerdINIWithUserTrust
        /// Jerd's INI with the local CA when it is available.
        case jerdINIWithLocalCA
    }

    /// The environment variables that choose TLS trust for cURL and OpenSSL.
    public static let trustVariables = ["SSL_CERT_FILE", "SSL_CERT_DIR", "CURL_CA_BUNDLE"]
    /// The environment variable that selects the INI file.
    public static let iniVariable = "PHPRC"
    /// The environment variable that selects the folder of additional INI files.
    public static let scanDirectoryVariable = "PHP_INI_SCAN_DIR"

    public let choice: Choice
    /// True when the launcher sets `PHP_INI_SCAN_DIR` to Jerd's empty folder.
    public let usesEmptyScanDirectory: Bool

    public init(command: CLICommand, arguments: [String], environment: [String: String]) {
        usesEmptyScanDirectory = environment[Self.scanDirectoryVariable] == nil
        if environment[Self.iniVariable] != nil || (command == .php && PHPINIArguments.selectINI(arguments)) {
            choice = .userINI
        } else if Self.trustVariables.contains(where: { environment[$0] != nil }) {
            choice = .jerdINIWithUserTrust
        } else {
            choice = .jerdINIWithLocalCA
        }
    }

    /// True when the launcher must prepare the local CA bundle.
    public var wantsLocalCA: Bool { choice == .jerdINIWithLocalCA }
}
