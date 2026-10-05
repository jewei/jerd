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
                "static_response", "vars", "file_server", "static_response", "rewrite", "reverse_proxy",
                "static_response", "file_server",
            ])
    }
}
