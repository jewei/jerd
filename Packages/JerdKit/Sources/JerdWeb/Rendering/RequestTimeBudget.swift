/// The one time budget of a PHP request, shared by PHP, PHP-FPM, and Caddy.
///
/// PHP and FPM end a request after 30 seconds. Caddy waits longer than that for the FastCGI
/// response, so PHP's own limit always decides first and the proxy never cuts a request that PHP
/// is still running (the old 15-second proxy limit was half the PHP limit).
public enum RequestTimeBudget {
    /// `max_execution_time` in the FPM `php.ini`.
    public static let phpExecutionSeconds = 30
    /// `request_terminate_timeout` of the FPM pool: the wall-clock limit of one worker request.
    public static let fpmTerminateSeconds = 30
    /// The Caddy FastCGI `read_timeout`: the FPM limit plus 5 seconds for the error response.
    public static let proxyReadSeconds = fpmTerminateSeconds + 5
    /// The Caddy FastCGI `dial_timeout`.
    public static let proxyDialSeconds = 3

    /// Caddy durations are integers of nanoseconds.
    static func nanoseconds(_ seconds: Int) -> Int { seconds * 1_000_000_000 }
}
