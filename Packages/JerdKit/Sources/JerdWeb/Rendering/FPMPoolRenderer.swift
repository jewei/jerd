import Foundation
import JerdFoundation

/// Renders the `php-fpm.conf` of one pool.
///
/// The file has no `user` or `group` line: FPM runs as the app user, and the engine refuses to
/// run as root. The socket is private (`listen.mode = 0600`) in a private folder.
public enum FPMPoolRenderer {
    /// FPM's built-in ping path. It runs no project file.
    public static let pingPath = "/.jerd/fpm-ping"
    /// The body of a successful ping.
    public static let pingResponse = "Jerd FPM is ready."

    /// - Throws: `.invalid` when the socket path is 104 bytes or longer, or cannot be quoted.
    public static func render(socket: URL) throws -> String {
        guard socket.path.utf8.count < RunLayout.socketPathLimit else {
            throw JerdError.invalid("PHP socket path is too long.")
        }
        return """
            [global]
            daemonize = no
            error_log = /dev/stderr
            log_level = notice
            process_control_timeout = 2s
            [jerd]
            listen = \(try INIString.quote(socket.path))
            listen.mode = 0600
            ping.path = \(pingPath)
            ping.response = \(pingResponse)
            pm = ondemand
            pm.max_children = 8
            pm.process_idle_timeout = 5s
            pm.max_requests = 100
            clear_env = yes
            catch_workers_output = yes
            security.limit_extensions = .php
            request_terminate_timeout = \(RequestTimeBudget.fpmTerminateSeconds)s
            chdir = /

            """
    }
}
