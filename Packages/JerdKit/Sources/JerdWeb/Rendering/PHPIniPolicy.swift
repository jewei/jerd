import Foundation

/// The PHP INI files of Jerd: shared defaults with explicit differences for FPM and the CLI.
///
/// The CLI target uses `cli` and `trustSection(caBundle:)` too, so both SAPIs keep one policy.
public enum PHPIniPolicy {
    /// The settings that both SAPIs share.
    public static let common = """
        [PHP]
        date.timezone = UTC
        expose_php = Off
        log_errors = On

        """

    /// The `php.ini` of every FPM pool (before the optional trust section).
    ///
    /// `cgi.fix_pathinfo = 1` (the PHP default, which Caddy's FastCGI transport expects): FPM then
    /// runs `SCRIPT_FILENAME`, the script that Caddy's routes selected. With `0`, FPM runs
    /// `PATH_TRANSLATED` instead, which is the document root plus the request's path info, so
    /// `/index.php/storage/upload.php` ran an upload and `/index.php/vendor/x.php` ran vendor code.
    /// Two independent layers close this, and the opt-in test
    /// `ScriptSelectionIntegrationTests` proved each one alone: this setting, and the PHP route,
    /// which sends path info only as `PATH_INFO` and never a `PATH_TRANSLATED`
    /// (`SiteRoutePolicy.phpRoute`). `security.limit_extensions = .php` in the pool file refuses
    /// any other extension.
    public static let fpm =
        common + """
            memory_limit = 256M
            upload_max_filesize = 32M
            post_max_size = 40M
            max_execution_time = \(RequestTimeBudget.phpExecutionSeconds)
            display_errors = Off
            cgi.fix_pathinfo = 1
            [opcache]
            opcache.enable = 1
            opcache.validate_timestamps = 1
            opcache.revalidate_freq = 0

            """

    /// The INI of the `php`, `composer`, and `laravel` commands (before the optional trust section).
    public static let cli =
        common + """
            memory_limit = -1
            max_execution_time = 0
            display_errors = stderr
            [opcache]
            opcache.enable_cli = 0

            """

    /// The cURL and OpenSSL CA file settings for the PHP CA bundle, or "" without a bundle.
    public static func trustSection(caBundle: URL?) throws -> String {
        guard let caBundle else { return "" }
        let path = try INIString.quote(caBundle.path)
        return "\n[curl]\ncurl.cainfo = \(path)\n[openssl]\nopenssl.cafile = \(path)\n"
    }

    /// The complete FPM `php.ini`.
    public static func fpmFile(caBundle: URL?) throws -> String {
        fpm + (try trustSection(caBundle: caBundle))
    }

    /// The complete CLI INI.
    public static func cliFile(caBundle: URL?) throws -> String {
        cli + (try trustSection(caBundle: caBundle))
    }
}
