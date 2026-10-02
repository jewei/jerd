import Foundation

public struct EnginePaths: Sendable {
    public let root: URL
    public let socketDirectory: URL
    public let installationID: UUID?
    private let socketName: String
    public var authorityID: String { installationID == nil ? "jerd-test" : "jerd" }
    public var configuration: URL { root.appendingPathComponent("configuration") }
    public var logs: URL { root.appendingPathComponent("logs") }
    public var storage: URL { root.appendingPathComponent("certificates") }
    public var socket: URL { socketDirectory.appendingPathComponent(socketName) }
    public var fpmConfig: URL { configuration.appendingPathComponent("php-fpm.conf") }
    public var phpINI: URL { configuration.appendingPathComponent("php.ini") }
    public var caddyConfig: URL { configuration.appendingPathComponent("caddy.json") }
    public var rootCertificate: URL { storage.appendingPathComponent("pki/authorities/\(authorityID)/root.crt") }
    public init(root: URL, socketDirectory: URL, installationID: UUID? = nil, socketName: String = "php.sock") {
        self.root = root; self.socketDirectory = socketDirectory; self.installationID = installationID; self.socketName = socketName
    }
}

public enum ConfigurationGenerator {
    public static let healthPath = "/.jerd/ready"
    public static let healthResponse = "Jerd is ready."
    public static let developmentINI = """
    [PHP]
    memory_limit = 256M
    upload_max_filesize = 32M
    post_max_size = 40M
    max_execution_time = 30
    date.timezone = UTC
    expose_php = Off
    display_errors = Off
    log_errors = On
    cgi.fix_pathinfo = 0
    [opcache]
    opcache.enable = 1
    opcache.validate_timestamps = 1
    opcache.revalidate_freq = 0

    """

    public static func fpm(paths: EnginePaths) throws -> String {
        guard paths.socket.path.utf8.count < 104 else { throw JerdError.invalid("PHP socket path is too long.") }
        return """
        [global]
        daemonize = no
        error_log = \(try iniQuote(paths.logs.appendingPathComponent("fpm-error.log").path))
        log_level = notice
        process_control_timeout = 2s
        [jerd]
        listen = \(try iniQuote(paths.socket.path))
        listen.mode = 0600
        pm = ondemand
        pm.max_children = 8
        pm.process_idle_timeout = 5s
        pm.max_requests = 100
        clear_env = yes
        catch_workers_output = yes
        security.limit_extensions = .php
        request_terminate_timeout = 30s
        chdir = /

        """
    }

    private static func iniQuote(_ value: String) throws -> String {
        guard !value.contains("${"), !value.unicodeScalars.contains(where: { $0.value < 32 }) else {
            throw JerdError.invalid("Configuration paths cannot contain control characters or environment substitutions.")
        }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    public static func caddy(site: Site, paths: EnginePaths, httpsPort: UInt16, httpPort: UInt16,
                             inheritedListeners: Bool = false) throws -> Data {
        try caddy(sites: [site], sockets: [site.id: paths.socket], paths: paths,
                  httpsPort: httpsPort, httpPort: httpPort, inheritedListeners: inheritedListeners)
    }

    public static func caddy(sites: [Site], sockets: [UUID: URL], paths: EnginePaths,
                             httpsPort: UInt16, httpPort: UInt16, inheritedListeners: Bool = false) throws -> Data {
        let hostnames = try Hostname.validatedSet(sites.map(\.hostname))
        guard httpsPort > 0, httpPort > 0, httpsPort != httpPort,
              inheritedListeners || (httpsPort > 1023 && httpPort > 1023) else {
            throw JerdError.invalid("Standard ports require approved, inherited loopback sockets.")
        }
        let authorityName = paths.installationID.map { "Jerd Local CA \($0.uuidString)" } ?? "Jerd isolated test CA"
        let redirectPort = httpsPort == 443 ? "" : ":\(httpsPort)"
        var secureRoutes: [[String: Any]] = []
        var redirectRoutes: [[String: Any]] = []
        for site in sites.sorted(by: { $0.hostname < $1.hostname }) {
            let hostname = try Hostname.validate(site.hostname)
            guard let socket = sockets[site.id] else { throw JerdError.invalid("A site's PHP socket is missing.") }
            secureRoutes.append(["match": [["host": [hostname]]],
                "handle": [["handler": "subroute", "routes": try applicationRoutes(site: site, socket: socket)]], "terminal": true])
            redirectRoutes.append(["match": [["host": [hostname]]],
                "handle": [["handler": "static_response", "status_code": 308,
                    "headers": ["Location": ["https://\(hostname)\(redirectPort){http.request.uri}"]]]]])
        }
        secureRoutes.append(["handle": [response(421)]])
        redirectRoutes.append(["handle": [response(421)]])
        let config: [String: Any] = [
            "admin": ["disabled": true],
            "storage": ["module": "file_system", "root": paths.storage.path],
            "apps": [
                "pki": ["certificate_authorities": [paths.authorityID: ["name": authorityName,
                        "root_common_name": authorityName, "install_trust": false]]],
                "tls": ["automation": ["policies": [["subjects": hostnames,
                    "issuers": [["module": "internal", "ca": paths.authorityID]]]]]],
                "http": ["http_port": Int(httpPort), "https_port": Int(httpsPort), "servers": [
                    "https": ["listen": [inheritedListeners ? "fd/4" : "127.0.0.1:\(httpsPort)"], "protocols": ["h1", "h2"],
                        "strict_sni_host": true, "automatic_https": ["disable_redirects": true],
                        "tls_connection_policies": [[String: Any]()], "routes": secureRoutes],
                    "http": ["listen": [inheritedListeners ? "fd/3" : "127.0.0.1:\(httpPort)"], "protocols": ["h1"],
                        "automatic_https": ["disable": true], "routes": redirectRoutes]
                ]]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    private static func response(_ code: Int) -> [String: Any] { ["handler": "static_response", "status_code": code] }

    private static func applicationRoutes(site: Site, socket: URL) throws -> [[String: Any]] {
        guard !site.documentRoot.contains("{"), !site.documentRoot.contains("}") else {
            throw JerdError.invalid("Jerd does not support braces in document-root paths.")
        }
        // A separate public root can expose Laravel's public/storage link.
        // Keep project-root storage private and never execute uploaded PHP.
        let privateDirectories = site.documentRoot == site.projectPath ? "(vendor|storage)" : "vendor"
        let deniedPaths = "(?i)(^|/)\\.|^/\(privateDirectories)(/|$)|(^|/)(composer\\.(json|lock)|auth\\.json)$|^/artisan$|^/storage/.*\\.php(/|$)|\\.php[^/]|\\.(phtml|phar|inc)(\\.|/|$)"
        return [
            ["match": [["path": [healthPath]]],
             "handle": [["handler": "static_response", "status_code": 200, "body": healthResponse]]],
            ["handle": [["handler": "vars", "root": site.documentRoot]]],
            // Reject backups before the file matcher can split their .php suffix.
            ["match": [["path_regexp": ["pattern": deniedPaths]]],
             "handle": [response(404)]],
            ["match": [["file": ["try_files": ["{http.request.uri.path}", "{http.request.uri.path}/index.php", "index.php"],
                                  "try_policy": "first_exist_fallback", "split_path": [".php"]]]],
             "handle": [["handler": "rewrite", "uri": "{http.matchers.file.relative}"]]],
            // Recheck storage after rewriting a directory URL to its index.php.
            ["match": [["path_regexp": ["pattern": "\\.php$"],
                         "not": [["path_regexp": ["pattern": "(?i)^/storage/"]]]]],
             "handle": [["handler": "reverse_proxy", "upstreams": [["dial": "unix/" + socket.path]],
                          "transport": ["protocol": "fastcgi", "root": site.documentRoot,
                                        "split_path": [".php"], "dial_timeout": 3_000_000_000,
                                        "read_timeout": 15_000_000_000]]]],
            // A PHP-like file can never fall through to the static file server.
            ["match": [["path_regexp": ["pattern": "(?i)\\.(php[0-9]*|phtml|phar|inc)(\\.|/|$)"]]],
             "handle": [response(404)]],
            ["handle": [["handler": "file_server", "hide": [".git", ".env", "*.php", "*.PHP", "*.phtml", "*.phar"]]]]
        ]
    }
}
