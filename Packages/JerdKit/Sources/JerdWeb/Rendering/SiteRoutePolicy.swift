import Foundation
import JerdFoundation

/// The request rules of one site, in the order Caddy evaluates them (the first match wins).
///
/// 1. `/.jerd/ready` answers 200 for readiness checks, before any other rule.
/// 2. The file root is set to the document root.
/// 3. An existing file below `/.well-known/` is served statically (see `wellKnownPattern`).
/// 4. Sensitive paths answer 404 (`deniedPathPattern`), before the file matcher can split `.php`.
/// 5. Missing files fall back to `index.php` (front controller).
/// 6. A path that ends in lowercase `.php`, outside `/storage/`, goes to PHP-FPM.
/// 7. Any other PHP-like file answers 404, so source never reaches the static server.
/// 8. Everything else is a static file, with source and secrets hidden.
public enum SiteRoutePolicy {
    /// The readiness path of the HTTPS server.
    public static let healthPath = "/.jerd/ready"
    /// The readiness body.
    public static let healthResponse = "Jerd is ready."
    /// Files that the static server never lists or serves.
    public static let hiddenFiles = [".git", ".env", "*.php", "*.PHP", "*.phtml", "*.phar"]

    /// Paths below `/.well-known/` (RFC 8615, lowercase) whose every segment is non-empty and does
    /// not start with a dot.
    ///
    /// Why this exact rule: security.txt, OAuth and OpenID discovery, and app-site association
    /// files must be reachable, so the old blanket dot-segment denial (spec B 7.1.2) is narrowed
    /// for this one prefix only. The route also requires an existing regular file and refuses
    /// every PHP-like or otherwise denied name, and it uses the static server only. So it can
    /// never run PHP, and a hidden file (`/.well-known/.env`) or a missing path still answers 404.
    public static let wellKnownPattern = "^/\\.well-known/([^./][^/]*/)*[^./][^/]*$"

    /// Any PHP-like file name, also with a suffix (`.php5`, `.phtml`, `.php.txt`, `.inc`).
    public static let phpLikePattern = "(?i)\\.(php[0-9]*|phtml|phar|inc)(\\.|/|$)"

    /// The 404 pattern: any dot segment, private folders, Composer files, `artisan`, PHP below
    /// `/storage/`, `.php` followed by anything but `/`, and PHP-like suffixes. Case-insensitive.
    /// `storage` is private too when the document root is the project root.
    public static func deniedPathPattern(servesProjectRoot: Bool) -> String {
        "(?i)(^|/)\\.|" + sensitiveAlternatives(servesProjectRoot: servesProjectRoot)
    }

    /// The denied pattern without the dot-segment rule. It also guards the `.well-known` route.
    static func sensitivePattern(servesProjectRoot: Bool) -> String {
        "(?i)" + sensitiveAlternatives(servesProjectRoot: servesProjectRoot)
    }

    private static func sensitiveAlternatives(servesProjectRoot: Bool) -> String {
        let privateFolders = servesProjectRoot ? "(vendor|storage)" : "vendor"
        return "^/\(privateFolders)(/|$)|(^|/)(composer\\.(json|lock)|auth\\.json)$|^/artisan$"
            + "|^/storage/.*\\.php(/|$)|\\.php[^/]|\\.(phtml|phar|inc)(\\.|/|$)"
    }

    /// The routes of one site, inside its host subroute.
    static func routes(for site: CaddySite) throws -> [JSONValue] {
        guard !site.documentRoot.contains("{"), !site.documentRoot.contains("}") else {
            throw JerdError.invalid("Jerd does not support braces in document-root paths.")
        }
        let root = JSONValue.string(site.documentRoot)
        return [
            ["match": [["path": [.string(healthPath)]]], "handle": [Self.response(200, body: healthResponse)]],
            ["handle": [["handler": "vars", "root": root]]],
            wellKnownRoute(site),
            [
                "match": [regexp(deniedPathPattern(servesProjectRoot: site.servesProjectRoot))],
                "handle": [response(404)],
            ],
            frontControllerRoute,
            phpRoute(site),
            ["match": [regexp(phpLikePattern)], "handle": [response(404)]],
            ["handle": [["handler": "file_server", "hide": .array(hiddenFiles.map(JSONValue.string))]]],
        ]
    }

    /// A static response handler.
    static func response(_ status: Int, body: String? = nil) -> JSONValue {
        var members: [String: JSONValue] = ["handler": "static_response", "status_code": .integer(status)]
        if let body { members["body"] = .string(body) }
        return .object(members)
    }

    private static func regexp(_ pattern: String) -> JSONValue {
        ["path_regexp": ["pattern": .string(pattern)]]
    }

    private static func wellKnownRoute(_ site: CaddySite) -> JSONValue {
        let refused: JSONValue = [
            regexp(sensitivePattern(servesProjectRoot: site.servesProjectRoot)), regexp(phpLikePattern),
        ]
        return [
            "match": [
                [
                    "path_regexp": ["pattern": .string(wellKnownPattern)], "not": refused,
                    "file": ["try_files": ["{http.request.uri.path}"], "try_policy": "first_exist"],
                ]
            ],
            "handle": [["handler": "file_server", "hide": .array(hiddenFiles.map(JSONValue.string))]],
        ]
    }

    private static let frontControllerRoute: JSONValue = [
        "match": [
            [
                "file": [
                    "try_files": ["{http.request.uri.path}", "{http.request.uri.path}/index.php", "index.php"],
                    "try_policy": "first_exist_fallback", "split_path": [".php"],
                ]
            ]
        ],
        "handle": [["handler": "rewrite", "uri": "{http.matchers.file.relative}"]],
    ]

    /// Case-sensitive `.php$`: an uppercase `.PHP` never reaches FastCGI. Storage is checked again
    /// after a directory URL was rewritten to its `index.php`.
    private static func phpRoute(_ site: CaddySite) -> JSONValue {
        [
            "match": [["path_regexp": ["pattern": "\\.php$"], "not": [regexp("(?i)^/storage/")]]],
            "handle": [
                [
                    "handler": "reverse_proxy", "upstreams": [["dial": .string("unix/" + site.socket.path)]],
                    "transport": [
                        "protocol": "fastcgi", "root": .string(site.documentRoot), "split_path": [".php"],
                        "dial_timeout": .integer(RequestTimeBudget.nanoseconds(RequestTimeBudget.proxyDialSeconds)),
                        "read_timeout": .integer(RequestTimeBudget.nanoseconds(RequestTimeBudget.proxyReadSeconds)),
                    ],
                ]
            ],
        ]
    }
}
