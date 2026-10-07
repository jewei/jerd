import Foundation
import Testing

@testable import JerdWeb

/// Pattern tables. Caddy uses Go RE2; these patterns use only syntax that RE2 and
/// `NSRegularExpression` read the same way.
@Suite struct SiteRoutePolicyTests {
    static func matches(_ pattern: String, _ path: String) throws -> Bool {
        try NSRegularExpression(pattern: pattern).firstMatch(in: path, range: NSRange(path.startIndex..., in: path))
            != nil
    }

    @Test(arguments: [
        "/.env", "/.git/config", "/%2eenv".removingPercentEncoding ?? "", "/a/.hidden", "/.well-known/x",
        "/index.php.bak", "/private.PHP.txt", "/file.phar", "/config.inc.bak", "/lib.phar.txt",
        "/packages/foo/auth.json", "/composer.json", "/sub/composer.lock", "/vendor", "/vendor/x.js", "/VENDOR/a",
        "/artisan", "/storage/upload.php", "/storage/a/b.php/extra", "/x.php5", "/x.phtml", "/x.inc",
        "/x.pht", "/x.PHT", "/x.pht.txt", "/x.phps", "/x.phpt",
    ])
    func theDenyPatternMatchesSensitivePaths(_ path: String) throws {
        #expect(try Self.matches(SiteRoutePolicy.deniedPathPattern(servesProjectRoot: false), path))
    }

    @Test(arguments: [
        "/index.php", "/index.php/route", "/js/app.include.js", "/hello.txt", "/storage/112/a.jpg", "/vendors.js",
        "/artisan.txt", "/public/composer.json.html",
    ])
    func theDenyPatternKeepsOrdinaryPaths(_ path: String) throws {
        #expect(try !Self.matches(SiteRoutePolicy.deniedPathPattern(servesProjectRoot: false), path))
    }

    @Test func storageIsPrivateOnlyWhenTheProjectRootIsServed() throws {
        #expect(
            try Self.matches(SiteRoutePolicy.deniedPathPattern(servesProjectRoot: true), "/storage/logs/laravel.log"))
        #expect(
            try !Self.matches(SiteRoutePolicy.deniedPathPattern(servesProjectRoot: false), "/storage/logs/laravel.log"))
    }

    @Test(arguments: [
        ("/.well-known/security.txt", true), ("/.well-known/openid-configuration", true),
        ("/.well-known/acme/a-b.json", true), ("/.well-known/.env", false), ("/.well-known/a/.git/config", false),
        ("/.well-known/", false), ("/.well-known", false), ("/.well-known//x", false), ("/.well-known/../x", false),
        ("/.WELL-KNOWN/x", false), ("/x/.well-known/y", false), ("/.well-knownx/y", false),
    ])
    func theWellKnownPatternAllowsOnlyVisibleSegments(_ path: String, _ allowed: Bool) throws {
        #expect(try Self.matches(SiteRoutePolicy.wellKnownPattern, path) == allowed)
    }

    @Test(arguments: [
        "/.well-known/x.php", "/.well-known/x.PHP", "/.well-known/x.php.txt", "/.well-known/x.phar",
        "/.well-known/a.inc", "/.well-known/composer.json", "/.well-known/x.php5",
    ])
    func theWellKnownRouteRefusesPHPLikeAndSensitiveNames(_ path: String) throws {
        let refused =
            try Self.matches(SiteRoutePolicy.sensitivePattern(servesProjectRoot: true), path)
            || Self.matches(SiteRoutePolicy.phpLikePattern, path)
        #expect(refused)
    }

    @Test func theRoutesKeepTheirOrder() throws {
        let site = try CaddySamples.appendixSites()[1]
        let routes = try SiteRoutePolicy.routes(for: site).map { route -> String in
            guard case .object(let members) = route, case .array(let handlers) = members["handle"],
                case .object(let handler) = handlers.first, case .string(let name) = handler["handler"]
            else { return "?" }
            return name
        }
        #expect(
            routes == [
                "static_response", "vars", "file_server", "static_response", "vars", "reverse_proxy",
                "static_response", "file_server",
            ])
    }

    @Test(arguments: [
        "/x.php", "/x.PHP", "/x.php7", "/x.pht", "/x.Pht", "/x.phtml", "/x.phar", "/x.phps", "/x.phpt", "/x.inc",
        "/x.php.txt", "/x.pht/y",
    ])
    func thePHPLikePatternCoversEveryExtensionThatServersTreatAsPHP(_ path: String) throws {
        #expect(try Self.matches(SiteRoutePolicy.phpLikePattern, path))
    }

    @Test(arguments: ["/x.phpx", "/x.photo", "/x.ph", "/include.js", "/x.html"])
    func thePHPLikePatternKeepsOtherNames(_ path: String) throws {
        #expect(try !Self.matches(SiteRoutePolicy.phpLikePattern, path))
    }

    @Test func theStaticServerHidesEveryPHPLikeName() {
        for name in ["*.php", "*.PHP", "*.php[0-9]", "*.pht", "*.phtml", "*.phar", "*.phps", "*.phpt", "*.inc"] {
            #expect(SiteRoutePolicy.hiddenFiles.contains(name), "\(name)")
        }
    }

    /// FPM gets path info only as `PATH_INFO`, never a `PATH_TRANSLATED`.
    @Test func pathInfoReachesPHPOnlyAsPathInfo() throws {
        let routes = try SiteRoutePolicy.routes(for: try CaddySamples.appendixSites()[1])
        let handlers = try #require(try Self.object(routes[4])["handle"]?.arrayValue)
        #expect(
            handlers.first
                == ["handler": "vars", SiteRoutePolicy.pathInfoVariable: "{http.matchers.file.remainder}"])
        let proxy = try #require(try Self.object(routes[5])["handle"]?.arrayValue?.first?.objectValue)
        let transport = try #require(proxy["transport"]?.objectValue)
        #expect(transport["env"] == ["PATH_INFO": "{http.vars.jerd_path_info}"])
        #expect(transport["split_path"] == [".php"])
        let text = String(decoding: try CaddySamples.appendixOutput(), as: UTF8.self)
        #expect(!text.contains("PATH_TRANSLATED"))
        #expect(PHPIniPolicy.fpm.contains("\ncgi.fix_pathinfo = 1\n"))
    }

    /// The PHP route compares the script's name on disk case-sensitively.
    @Test func thePHPRouteRequiresTheExactLowercaseNameOnDisk() throws {
        let routes = try SiteRoutePolicy.routes(for: try CaddySamples.appendixSites()[1])
        let match = try #require(try Self.object(routes[5])["match"]?.arrayValue?.first?.objectValue)
        #expect(match["path_regexp"] == ["pattern": "\\.php$"])
        #expect(
            match["file"]
                == [
                    "try_files": ["{http.request.uri.path.dir}{http.request.uri.path.file.base}.ph[p]"],
                    "try_policy": "first_exist",
                ])
    }

    private static func object(_ value: JSONValue) throws -> [String: JSONValue] {
        try #require(value.objectValue)
    }
}

extension JSONValue {
    fileprivate var objectValue: [String: JSONValue]? {
        if case .object(let members) = self { return members }
        return nil
    }

    fileprivate var arrayValue: [JSONValue]? {
        if case .array(let items) = self { return items }
        return nil
    }
}
